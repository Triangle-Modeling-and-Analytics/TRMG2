/*
Handle initial steps like capacity and speed calculations.
*/

Macro "Create Initial Output Files" (Args)
    created = RunMacro("Is Scenario Created", Args)
    if !created then return(0)
    RunMacro("Create Output Copies", Args)
    RunMacro("Filter Transit Modes", Args)
    RunMacro("Check SE Data", Args)
    return(1)
EndMacro

Macro "Area Type" (Args)
    RunMacro("Determine Area Type", Args)
    return(1)
endmacro

Macro "Capacities" (Args)
    RunMacro("Capacity", Args)
    return(1)
endmacro

Macro "Speeds & Tolls" (Args)
    RunMacro("Set CC Speeds", Args)
    RunMacro("Other Attributes", Args)
    RunMacro("Calculate Bus Speeds", Args)
    return(1)
endmacro

Macro "Network Creation" (Args)
    RunMacro("Create Link Networks", Args)
    RunMacro("Check Highway Networks", Args)
    RunMacro("Create Route Networks", Args)
    return(1)
endmacro

/*
This macro checks that the current scenario is created. If output already
exists, checks to make sure you want to overwrite it. This is most commonly
encountered when you create a new scenario but forget to change the
scenario folder to the new location. This check prevents you from accidently
overwriting your already-run scenario.
*/

Macro "Is Scenario Created" (Args)

    scen_dir = Args.[Scenario Folder]
    if GetFileInfo(Args.SE) <> null then do
        yesno = MessageBox(
            "This scenario already has output data\n" + 
            "Scenario folder:\n" +
            scen_dir + "\n" + 
            "Do you want to overwrite?",
            {Buttons: "YesNo", Caption: "Overwrite scenario?"}
        )
        if yesno = "No" then return("false")
    end

    input_files_to_check = {
        Args.[Input Links],
        Args.[Input Routes],
        Args.[Input SE]
    }
    scenario_created = "true"
    for file in input_files_to_check do
        if GetFileInfo(file) = null then scenario_created = "false"
    end
    if scenario_created then return("true")
    else do
        MessageBox(
            "This scenario has not been created\n" + 
            "Use TRMG2 Menu -> Create Scenario",
            {Caption: "Scenario not created"}
        )
        return("false")
    end
endmacro

/*
Creates copies of the scenario/input SE, TAZs, and networks.
The model will modify the output copy, leaving
the input files as they were.  This helps when looking back at
older scenarios.
*/

Macro "Create Output Copies" (Args)

    opts = null
    opts.from_rts = Args.[Input Routes]
    {drive, folder, filename, ext} = SplitPath(Args.Routes)
    opts.to_dir = drive + folder
    opts.include_hwy_files = "true"
    RunMacro("Copy RTS Files", opts)
    CopyDatabase(Args.[Input TAZs], Args.TAZs)
    se = OpenTable("se", "FFB", {Args.[Input SE]})
    ExportView(se + "|", "FFB", Args.SE, , )
    CloseView(se)
EndMacro


/*
Remove modes from the mode table that don't exist in the scenario. This
will in turn control which networks (tnw) get created.
*/

Macro "Filter Transit Modes" (Args)
        
    rts_file = Args.Routes
    opts.file = rts_file
    {map, {rlyr, slyr, , nlyr, llyr}} = RunMacro("Create Map", opts)
    
    temp_vw = OpenTable("mode", "CSV", {Args.TransModeTable, })
    mode_vw = ExportView(temp_vw + "|", "MEM", "mode_table", , )
    SetView(mode_vw)
    del_set = CreateSet("to_delete")
    CloseView(temp_vw)
    v_mode_ids = GetDataVector(mode_vw + "|", "mode_id", )
    for mode_id in v_mode_ids do
        if mode_id = 1 then continue
        SetLayer(rlyr)
        query = "Select * where Mode = " + String(mode_id)
        n = SelectByQuery("sel", "several", query)
        if n = 0 then do
            SetView(mode_vw)
            rh = LocateRecord(mode_vw + "|", "mode_id", {mode_id}, )
            SelectRecord(del_set)
        end
    end
    SetView(mode_vw)
    DeleteRecordsInSet(del_set)
    ExportView(mode_vw + "|", "CSV", Args.TransModeTable, , {"CSV Header": "true"})
    CloseView(mode_vw)
    DeleteFile(Substitute(Args.TransModeTable, ".csv", ".dcc", ))
    
    // Remove modes from MC parameter files
    RunMacro("Filter Resident HB Transit Modes", Args)
    
    CloseMap(map)
endmacro


/*
Removes modes from the resident HB csv parameter files if they don't exist
in the scenario.
*/

Macro "Filter Resident HB Transit Modes" (Args)
    
    mode_table = Args.TransModeTable
    access_modes = Args.access_modes
    mc_dir = Args.[Input Folder] + "/resident/mode"
    
    transit_modes = RunMacro("Get Transit Modes", mode_table)
    trip_types = RunMacro("Get HB Trip Types", Args)
    for trip_type in trip_types do
        nest_file = mc_dir + "/" + trip_type + "_nest.csv"
        coef_file = mc_dir + "/" + trip_type + ".csv"

        // Filter coefficient file
        coef_vw = OpenTable("coef", "CSV", {coef_file})
        SetView(coef_vw)
        // Start by selecting all non-transit modes
        query = "Select * where"
        for i = 1 to access_modes.length do
            access = access_modes[i]
            if i = 1 then query = query + " not(Alternative contains '" + access + "_')"
            else query = query + " and not(Alternative contains '" + access + "_')"
        end
        SelectByQuery("export", "more", query)
        // Now add transit modes that exist to the selection
        for mode in transit_modes do
            for access in access_modes do
                alt = access + "_" + mode
                query = "Select * where Alternative = '" + alt + "'"
                SelectByQuery("export", "more", query)
            end
        end
        out_file = Substitute(coef_file, ".csv", "_copy.csv", )
        out_file = Lower(out_file)
        ExportView(coef_vw + "|export", "CSV", out_file, , {"CSV Header": "true"})
        CloseView(coef_vw)
        DeleteFile(coef_file)
        CopyFile(out_file, coef_file)
        DeleteFile(out_file)

        // Filter nest file
        vw_temp = OpenTable("temp", "CSV", {nest_file})
        nest_vw = ExportView(vw_temp + "|", "MEM", "nest", , )
        CloseView(vw_temp)
        v_orig = GetDataVector(nest_vw + "|", "Alternatives", )
        v_final = v_orig
        for i = 1 to v_orig.length do
            str_orig = v_orig[i]
            parts = ParseString(str_orig, ", ")
            str_final = ""
            for part in parts do
                // Determine if this part is a transit mode
                transit = 0
                for access in access_modes do
                    if Position(part, access + "_") > 0 then do
                        transit = 1
                        break
                    end
                end
                // Keep all non-transit modes
                if !transit then str_final = str_final + ", " + part
                // Only keep transit modes that are present in this scenario
                if transit then do
                    {access, mode} = ParseString(part, "_")
                    if transit_modes.position(mode) > 0 
                        then str_final = str_final + ", " + part
                end
            end
            str_final = Right(str_final, StringLength(str_final) - 2)
            v_final[i] = str_final
        end

        SetDataVector(nest_vw + "|", "Alternatives", v_final, )
        ExportView(nest_vw + "|", "CSV", nest_file, , {"CSV Header": "true"})
        CloseView(nest_vw)
    end
endmacro

/*
Checks the SE data for logical problems
*/

Macro "Check SE Data" (Args)

    se_bin = Args.SE

    se_vw = OpenTable("se", "FFB", {se_bin})
    SetView(se_vw)
    
    // Internal checks
    query = "Select * where Type = 'Internal'"
    n = SelectByQuery("internal", "several", query)
    if n = 0 then Throw("No internal zones found (query = '" + query + "')")
    fields = {"HH", "HH_POP", "Median_Inc", "Pct_Worker", "Pct_Child", "Pct_Senior"}
    data = GetDataVectors(
        se_vw + "|internal", fields,
        {OptArray: "true", "Missing As Zero": "true"}
    )
    if RunMacro("Any True", data.HH > 0 and data.HH_POP = 0) 
        then Throw("SE Check: Zones with households are missing population")
    if RunMacro("Any True", data.HH_POP > 0 and data.HH = 0)
        then Throw("SE Check: Zones with population are missing households")
    if RunMacro("Any True", data.HH > 0 and data.Median_Inc = 0)
        then Throw("SE Check: Zones with households are missing median income")
    if RunMacro("Any True", data.HH > 0 and data.HH_POP / data.HH < 1)
        then Throw("SE Check: Some zones have fewer than 1 person per household")
    if RunMacro("Any True", data.Pct_worker > 100)
        then Throw("SE Check: Zones have 'Pct_Worker' > 100")
    if RunMacro("Any True", data.Pct_Child > 100)
        then Throw("SE Check: Zones have 'Pct_Child' > 100")
    if RunMacro("Any True", data.Pct_Senior > 100)
        then Throw("SE Check: Zones have 'Pct_Senior' > 100")
                
    CloseView(se_vw)
endmacro

/*
Helper macro for se check. Checks if any member of a vector is true.
*/

Macro "Any True" (v)
    if v.position(1) <> 0 then return("true")
endmacro

/*
Prepares input options for the AreaType.rsc library of tools, which
tags TAZs and Links with area types.
*/

Macro "Determine Area Type" (Args)

    scen_dir = Args.[Scenario Folder]
    taz_dbd = Args.TAZs
    se_bin = Args.SE
    hwy_dbd = Args.Links
    area_tbl = Args.AreaTypes

    // Get area from TAZ layer
    {map, {taz_lyr}} = RunMacro("Create Map", {file: taz_dbd})

    // Calculate total employment and density
    se_vw = OpenTable("se", "FFB", {se_bin, })
    a_fields =  {
        {"TotalEmp", "Integer", 10, ,,,, "Total employment"},
        {"Density", "Real", 10, 2,,,, "Density used in area type calculation.|Considers HH and Emp."},
        {"AreaType", "Character", 10,,,,, "Area Type"},
        {"ATSmoothed", "Integer", 10,,,,, "Whether or not the area type was smoothed"},
        {"EmpDensity", "Real", 10, 2,,,, "Employment density. Used in some DC models.|TotalEmp / Area."}
    }
    RunMacro("Add Fields", {view: se_vw, a_fields: a_fields})

    // Join the se to TAZ
    jv = JoinViews("jv", taz_lyr + ".ID", se_vw + ".TAZ", )

    data = GetDataVectors(
        jv + "|",
        {
            "Area",
            "HH",
            "HH_POP",
            "Industry",
            "Office",
            "Service_RateLow",
            "Service_RateHigh",
            "Retail"
        },
        {OptArray: TRUE, "Missing as Zero": TRUE}
    )
    tot_emp = data.Industry + data.Office + data.Service_RateLow + 
        data.Service_RateHigh + data.Retail
    factor = data.HH_POP.sum() / tot_emp.sum()
    density = (data.HH_POP + tot_emp * factor) / data.area
    emp_density = tot_emp / data.area
    areatype = Vector(density.length, "String", )
    for i = 1 to area_tbl.length do
        name = area_tbl[i].AreaType
        cutoff = area_tbl[i].Density
        areatype = if density >= cutoff then name else areatype
    end
    SetDataVector(jv + "|", "TotalEmp", tot_emp, )
    SetDataVector(jv + "|", se_vw + ".Density", density, )
    SetDataVector(jv + "|", se_vw + ".AreaType", areatype, )
    SetDataVector(jv + "|", se_vw + ".EmpDensity", emp_density, )

    views.se_vw = se_vw
    views.jv = jv
    views.taz_lyr = taz_lyr
    RunMacro("Smooth Area Type", Args, map, views)
    RunMacro("Tag Highway with Area Type", Args, map, views)

    CloseView(jv)
    CloseView(se_vw)
    CloseMap(map)
EndMacro

/*
Uses buffers to smooth the boundaries between the different area types.
*/

Macro "Smooth Area Type" (Args, map, views)
    
    taz_dbd = Args.TAZs
    area_tbl = Args.AreaTypes
    se_vw = views.se_vw
    jv = views.jv
    taz_lyr = views.taz_lyr

    // This smoothing operation uses Enclosed inclusion
    if GetSelectInclusion() = "Intersecting" then do
        reset_inclusion = TRUE
        SetSelectInclusion("Enclosed")
    end

    // Loop over the area types in reverse order (e.g. Urban to Rural)
    // Skip the last (least dense) area type (usually "Rural") as those do
    // not require buffering.
    for t = area_tbl.length to 2 step -1 do
        type = area_tbl[t].AreaType
        buffer = area_tbl[t].Buffer

        // Select TAZs of current type
        SetView(jv)
        query = "Select * where " + se_vw + ".AreaType = '" + type + "'"
        n = SelectByQuery("selection", "Several", query)

        if n > 0 then do
            // Create a temporary buffer (deleted at end of macro)
            // and add to map.
            a_path = SplitPath(taz_dbd)
            bufferDBD = a_path[1] + a_path[2] + "ATbuffer.dbd"
            CreateBuffers(bufferDBD, "buffer", {"selection"}, "Value", {buffer},)
            bLyr = AddLayer(map,"buffer",bufferDBD,"buffer")

            // Select zones within the 1 mile buffer that have not already
            // been smoothed.
            SetLayer(taz_lyr)
            n2 = SelectByVicinity("in_buffer", "several", "buffer|", , )
            qry = "Select * where ATSmoothed = 1"
            n2 = SelectByQuery("in_buffer", "Less", qry)

            if n2 > 0 then do
            // Set those zones' area type to the current type and mark
            // them as smoothed
            opts = null
            opts.Constant = type
            v_atype = Vector(n2, "String", opts)
            opts = null
            opts.Constant = 1
            v_smoothed = Vector(n2, "Long", opts)
            SetDataVector(
                jv + "|in_buffer", se_vw + "." + "AreaType", v_atype,
            )
            SetDataVector(
                jv + "|in_buffer", se_vw + "." + "ATSmoothed", v_smoothed,
            )
            end

            DropLayer(map, bLyr)
            DeleteDatabase(bufferDBD)
        end
    end

    if reset_inclusion then SetSelectInclusion("Intersecting")
EndMacro

/*
Tags highway links with the area type of the TAZ they are nearest to.
*/

Macro "Tag Highway with Area Type" (Args, map, views)

    hwy_dbd = Args.Links
    area_tbl = Args.AreaTypes
    se_vw = views.se_vw
    jv = views.jv
    taz_lyr = views.taz_lyr

    // This smoothing operation uses intersecting inclusion.
    // This prevents links inbetween urban and surban from remaining rural.
    if GetSelectInclusion() = "Enclosed" then do
        reset_inclusion = "true"
        SetSelectInclusion("Intersecting")
    end

    // Add highway links to map and add AreaType field
    hwy_dbd = hwy_dbd
    {nLayer, llyr} = GetDBLayers(hwy_dbd)
    llyr = AddLayer(map, llyr, hwy_dbd, llyr)
    a_fields = {{"AreaType", "Character", 10, }}
    RunMacro("Add Fields", {view: llyr, a_fields: a_fields})
    SetLayer(llyr)
    SelectByQuery("primary", "several", "Select * where DTWB contains 'D' or DTWB contains 'T'")

    // Loop over each area type starting with most dense.  Skip the first.
    // All remaining links after this loop will be tagged with the lowest
    // area type. Secondary links (walk network) not tagged.
    for t = area_tbl.length to 2 step -1 do
        type = area_tbl[t].AreaType

        // Select TAZs of current type
        SetView(jv)
        query = "Select * where " + se_vw + ".AreaType = '" + type + "'"
        n = SelectByQuery("selection", "Several", query)

        if n > 0 then do
            // Create buffer and add it to the map
            buffer_dbd = GetTempFileName(".dbd")
            opts = null
            opts.Exterior = "Merged"
            opts.Interior = "Merged"
            CreateBuffers(buffer_dbd, "buffer", {"selection"}, "Value", {100/5280}, )
            bLyr = AddLayer(map, "buffer", buffer_dbd, "buffer")

            // Select links within the buffer that haven't been updated already
            SetLayer(llyr)
            n2 = SelectByVicinity(
                "links", "several", taz_lyr + "|selection", 0, 
                {"Source And": "primary"}
            )
            query = "Select * where AreaType <> null"
            n2 = SelectByQuery("links", "Less", query)

            // Remove buffer from map
            DropLayer(map, bLyr)

            if n2 > 0 then do
                // For these links, update their area type
                v_at = Vector(n2, "String", {{"Constant", type}})
                SetDataVector(llyr + "|links", "AreaType", v_at, )
            end
        end
    end

    // Select all remaining links and assign them to the
    // first (lowest density) area type.
    SetLayer(llyr)
    query = "Select * where AreaType = null and (DTWB contains 'D' or DTWB contains 'T')"
    n = SelectByQuery("links", "Several", query)
    if n > 0 then do
        type = area_tbl[1].AreaType
        v_at = Vector(n, "String", {{"Constant", type}})
        SetDataVector(llyr + "|links", "AreaType", v_at, )
    end

    // If this script modified the user setting for inclusion, change it back.
    if reset_inclusion = "true" then SetSelectInclusion("Enclosed")
EndMacro

/*
Determine link capacities
*/

Macro "Capacity" (Args)

    link_dbd = Args.Links
    cap_file = Args.Capacity
    capfactors_file = Args.CapacityFactors

    // Create a map and add fields to be filled in
    {map, {node_lyr, link_lyr}} = RunMacro("Create Map", {file: link_dbd})
    a_fields =  {
        {"capd_phpl", "Integer", 10, ,,,, 
        "LOS D capacity per hour per lane|LOS E is used for assignment."},
        {"cape_phpl", "Integer", 10, ,,,, 
        "LOS E capacity per hour per lane|LOS E is used for assignment."}
    }
    RunMacro("Add Fields", {view: link_lyr, a_fields: a_fields})
    {link_fields, link_specs} = RunMacro("Get Fields", {view_name: link_lyr})

    // // Assign facility type to ramps
    SetLayer(link_lyr)
    ramp_query = "Select * where HCMType = 'Ramp'"
    n = SelectByQuery("sel", "several", ramp_query)
    if n > 0 then do
        fac_field = "HCMType"
        a_ft_priority = {
            "Freeway",
            "MajorArterial",
            "Arterial",
            "MajorCollector",
            "Collector",
            "Superstreet",
            "MLHighway",
            "TLHighway"
        }
        RunMacro("Assign FT to Ramps", link_lyr, node_lyr, ramp_query, fac_field, a_ft_priority)
    end

    // Override median values for certain HCM types
    hcm_type = GetDataVector(link_lyr + "|", "HCMType", )
    hcm_med = GetDataVector(link_lyr + "|", "HCMMedian", )
    hcm_med = if hcm_type = "Freeway" then "Restrictive"
        else if hcm_type = "MLHighway" then "Restrictive"
        else if hcm_type = "TLHighway" then "None"
        else if hcm_type = "Superstreet" then "Restrictive"
        else if hcm_type = "CC" then "None"
        else if hcm_type <> null and hcm_med = null then "None"
        else hcm_med
    SetDataVector(link_lyr + "|", "HCMMedian", hcm_med, )

    // Add hourly capacity to link layer
    cap_vw = OpenTable("cap", "CSV", {cap_file})
    {cap_fields, cap_specs} = RunMacro("Get Fields", {view_name: cap_vw})
    jv = JoinViewsMulti(
        "jv", 
        {link_specs.HCMType, link_specs.AreaType, link_specs.HCMMedian},
        {cap_specs.HCMType, cap_specs.AreaType, cap_specs.HCMMedian},
        null
    )
    capd = GetDataVector(jv + "|", cap_specs.capd_phpl, )
    cape = GetDataVector(jv + "|", cap_specs.cape_phpl, )
    SetDataVector(jv + "|", link_specs.capd_phpl, capd, )
    SetDataVector(jv + "|", link_specs.cape_phpl, cape, )
    CloseView(jv)
    CloseView(cap_vw)

    // Determine period capacities
    factor_vw = OpenTable("factors", "CSV", {capfactors_file})
    {fac_fields, fac_specs} = RunMacro("Get Fields", {view_name: factor_vw})
    v_periods = GetDataVector(factor_vw + "|", "TOD", )
    v_factors = GetDataVector(factor_vw + "|", "Value", )
    CloseView(factor_vw)
    a_los = {"D", "E"}
    a_dir = {"AB", "BA"}
    for los in a_los do
        for i = 1 to v_periods.length do
            period = v_periods[i]
            factor = v_factors[i]
        
            for dir in a_dir do
                hourly_field_name = dir + period + "Cap" + los + "_h"
                period_field_name = dir + period + "Cap" + los
                a_fields = {
                    {hourly_field_name , "Integer", 10,,,,, "Hourly LOS " + los + " Capacity"},
                    {period_field_name, "Integer", 10,,,,, "Period LOS " + los + " Capacity"}
                }
                RunMacro("Add Fields", {view: link_lyr, a_fields: a_fields})

                v_phpl = GetDataVector(link_lyr + "|", "cap" + Lower(los) + "_phpl", )
                v_lanes = GetDataVector(link_lyr + "|", dir + "Lanes", )
                v_hourly = v_phpl * v_lanes
                v_period = v_hourly * factor
                data.(hourly_field_name) = v_hourly
                data.(period_field_name) = v_period
            end
        end
    end
    SetDataVectors(link_lyr + "|", data, )

    CloseMap(map)
endmacro

/*
This macro assigns ramp facility types to the highest FT they connect to.
It also creates a new field to mark the links as ramps so that info is not lost.

Input:
hwy_dbd     String  Full path of the highway geodatabase
ramp_query  String  Query defining which links are ramps
                    e.g. "Select * where Ramp = 1"
ftField     String  Name of the facility type field to use
                    e.g. "HCMType"
a_ftOrder   Array   Order of FT from highest to lowest
                    e.g. {"Freeway", "PrArterial", "Local"}

Output:
Changes the ftField of the ramp links to the FT to use for capacity calculation.
*/

Macro "Assign FT to Ramps" (llyr, nlyr, ramp_query, ftField, a_ftOrder)

    SetLayer(llyr)
    n1 = SelectByQuery("ramps", "Several", ramp_query)

    if n1 = 0 then do
        Throw("No ramp links found.")
    end else do
    
        // Create a new field to identify these links as ramps
        // after their facility type is changed.
        a_fields = {
            {"ramp", "Character", 10, ,,,,"Is this link a ramp?"}
        }
        RunMacro("Add Fields", {view: llyr, a_fields: a_fields})
        opts = null
        opts.Constant = "Yes"
        v = Vector(n1, "String", opts)
        SetDataVector(llyr + "|ramps", "ramp", v, )
    
        // Get ramp ids and loop over each one
        v_rampIDs = GetDataVector(llyr + "|ramps", "ID", )
        for r = 1 to v_rampIDs.length do
            rampID = v_rampIDs[r]

            minPos = 999
            SetLayer(llyr)
            a_rampNodeIDs = GetEndPoints(rampID)
            for n = 1 to a_rampNodeIDs.length do
                rampNodeID = a_rampNodeIDs[n]

                SetLayer(nlyr)
                a_linkIDs = GetNodeLinks(rampNodeID)
                for l = 1 to a_linkIDs.length do
                    id = a_linkIDs[l]

                    SetLayer(llyr)
                    opts = null
                    opts.Exact = "True"
                    rh = LocateRecord(llyr + "|", "ID", {id}, opts)
                    ft = llyr.(ftField)
                    pos = ArrayPosition(a_ftOrder, {ft}, )
                    if pos = 0 then pos = 999
                    minPos = min(minPos, pos)
                end
            end

            // If a ramp is only connected to other ramps, code as highest FT
            if minPos = 999 then a_ft = a_ft + {a_ftOrder[1]}
            else a_ft = a_ft + {a_ftOrder[R2I(minPos)]}
        end
    end

    SetDataVector(llyr + "|ramps", ftField, A2V(a_ft), )
EndMacro

/*
Set CC speed by area type to be more realistic
*/

Macro "Set CC Speeds" (Args)

    links_dbd = Args.Links
    scen_dir = Args.[Scenario Folder]
    cc_speeds = Args.CCSpeeds

    // Add link layer to workspace
    objLyrs = CreateObject("AddDBLayers", {FileName: links_dbd})
    {nlyr, llyr} = objLyrs.Layers

    // Create a selection set of centroid connectors
    SetLayer(llyr)
    qry = "Select * where HCMType = 'CC'"
    n = SelectByQuery("CCs", "Several", qry)

    // Update speeds
    v_speed = GetDataVector(llyr + "|CCs", "PostedSpeed", )
    v_at = GetDataVector(llyr + "|CCs", "AreaType", )
    for i = 1 to cc_speeds.length do
        at = cc_speeds[i].AreaType
        speed = cc_speeds[i].Speed

        v_speed = if v_at = at then speed else v_speed
    end
    SetDataVector(llyr + "|CCs", "PostedSpeed", v_speed, )
EndMacro

/*
Other important fields like FFS and FFT, walk time, etc. Also determines which
nodes can be KNR.
*/

Macro "Other Attributes" (Args)
    
    rts_file = Args.Routes
    scen_dir = Args.[Scenario Folder]
    spd_file = Args.SpeedFactors
    congtime_file = Args.InitCongTimes
    periods = RunMacro("Get Unconverged Periods", Args)
    trans_ratio_auto = Args.TransponderRatioAuto
    trans_ratio_sut = Args.TransponderRatioSUT
    trans_ratio_mut = Args.TransponderRatioMUT
    se_file = Args.SE
    taz_file = Args.TAZs

    {map, {rlyr, slyr, , nlyr, llyr}} = RunMacro("Create Map", {file: rts_file})
    
    a_fields = {
        {"TollCostSOV", "Real", 10, 2, , , , "TollCost|TollCost Influenced by TransponderRatioAuto"},
        {"TollCostHOV", "Real", 10, 2, , , , "Same as TollCostSOV, but HOT lanes are free."},
        {"TollCostSUT", "Real", 10, 2, , , , "TollCost * 2|TollCost Influenced by TransponderRatioSUT"},
        {"TollCostMUT", "Real", 10, 2, , , , "TollCost * 4|TollCost Influenced by TransponderRatioMUT"},
        {"D", "Integer", 10, , , , , "If drive mode is allowed (from DTWB column)"},
        {"T", "Integer", 10, , , , , "If transit mode is allowed (from DTWB column)"},
        {"W", "Integer", 10, , , , , "If walk mode is allowed (from DTWB column)"},
        {"B", "Integer", 10, , , , , "If bike mode is allowed (from DTWB column)"},
        {"Alpha", "Real", 10, 2, , , , "VDF alpha value"},
        {"Beta", "Real", 10, 2, , , , "VDF beta value"},
        {"WalkTime", "Real", 10, 2, , , , "Length / 3 mph|Unless overriden by WalkSpeed field"},
        {"BikeTime", "Real", 10, 2, , , , "Length / 15 mph|Unless overriden by BikeSpeed field"},
        {"Mode", "Integer", 10, , , , , "Marks all links with a 1 (nontransit mode)"},
        {"FFSpeed", "Integer", 10, , , , , "Free flow travel speed"},
        {"FFTime", "Real", 10, 2, , , , "Free flow travel time"}
    }
    for period in periods do
        a_fields = a_fields + {
            {"AB" + period + "Time", "Real", 10, 2, , , , 
            "Congested time in the " + period + " period.|Updated after each assignment."},
            {"BA" + period + "Time", "Real", 10, 2, , , , 
            "Congested time in the " + period + " period.|Updated after each assignment."}
        }
    end
    RunMacro("Add Fields", {view: llyr, a_fields: a_fields})

    // Open parameter table
    ffs_tbl = OpenTable("ffs", "CSV", {spd_file, })

    // Join based on AreaType and HCMType
    jv = JoinViewsMulti(
        "jv",
        {llyr + ".AreaType", llyr + ".HCMType"},
        {ffs_tbl + ".AreaType", ffs_tbl + ".HCMType"},
    )

    // Perform calculations
    {v_dir, v_type, v_len, v_ps, v_walkspeed, v_bikespeed, v_tolltype, v_tollcost_t, v_tollcost_nt, v_mod, v_alpha, v_beta} = GetDataVectors(
        jv + "|", {
            llyr + ".Dir",
            llyr + ".HCMType",
            llyr + ".Length",
            llyr + ".PostedSpeed",
            llyr + ".WalkSpeed",
            llyr + ".BikeSpeed",
            llyr + ".TollType",
            llyr + ".TollCostT",
            llyr + ".TollCostNT",
            ffs_tbl + ".ModifyPosted",
            ffs_tbl + ".Alpha",
            ffs_tbl + ".Beta"
            },
        )
    v_ffs = v_ps + v_mod
    v_fft = v_len / v_ffs * 60
    v_walkspeed = if v_walkspeed = null then 3 else v_walkspeed
    v_wt = v_len / v_walkspeed * 60
    v_bikespeed = if v_bikespeed = null then 15 else v_bikespeed
    v_bt = v_len / v_bikespeed * 60
    v_mode = Vector(v_wt.length, "Integer", {Constant: 1})
    // Determine weighted average toll cost based on transponder usage
    v_tollcost_auto = v_tollcost_t * trans_ratio_auto + v_tollcost_nt * (1 - trans_ratio_auto)
    v_tollcost_auto = if v_tolltype = "Free" then 0 else v_tollcost_auto
    v_tollcost_hov = if v_tolltype = "HOT" then 0 else v_tollcost_auto
    v_tollcost_sut = v_tollcost_t * trans_ratio_sut + v_tollcost_nt * (1 - trans_ratio_sut)
    v_tollcost_sut = v_tollcost_sut * 2
    v_tollcost_sut = if v_tolltype = "Free" then 0 else v_tollcost_sut
    v_tollcost_mut = v_tollcost_t * trans_ratio_mut + v_tollcost_nt * (1 - trans_ratio_mut)
    v_tollcost_mut = v_tollcost_mut * 4
    v_tollcost_mut = if v_tolltype = "Free" then 0 else v_tollcost_mut
    SetDataVector(jv + "|", llyr + ".FFSpeed", v_ffs, )
    SetDataVector(jv + "|", llyr + ".FFTime", v_fft, )
    SetDataVector(jv + "|", llyr + ".Alpha", v_alpha, )
    SetDataVector(jv + "|", llyr + ".Beta", v_beta, )
    SetDataVector(jv + "|", llyr + ".WalkTime", v_wt, )
    SetDataVector(jv + "|", llyr + ".BikeTime", v_bt, )
    SetDataVector(jv + "|", llyr + ".Mode", v_mode, )
    SetDataVector(jv + "|", llyr + ".TollCostSOV", v_tollcost_auto, )
    SetDataVector(jv + "|", llyr + ".TollCostHOV", v_tollcost_hov, )
    SetDataVector(jv + "|", llyr + ".TollCostSUT", v_tollcost_sut, )
    SetDataVector(jv + "|", llyr + ".TollCostMUT", v_tollcost_mut, )
    
    // Initial congested time
    // The initial congested time table contains a field which holds converged congested times
    // from a run done during model development. This helps to speed up the model run
    // by reducing the number of large feedback loops required. If a link does not have
    // a value stored in this field, the FFT is used.
    v_ab_time = if v_dir = 1 or v_dir = 0 then v_fft
    v_ba_time = if v_dir = -1 or v_dir = 0 then v_fft
    for period in periods do
        SetDataVector(jv + "|", llyr + ".AB" + period + "Time", v_ab_time, )
        SetDataVector(jv + "|", llyr + ".BA" + period + "Time", v_ba_time, )
    end
    CloseView(jv)
    time_vw = OpenTable("times", "FFB", {congtime_file})
    jv = JoinViews("jv", llyr + ".ID", time_vw + ".ID", )
    dirs = {"AB", "BA"}
    for period in periods do
        for dir in dirs do
            v_time = GetDataVector(jv + "|", llyr + "." + dir + period + "Time", )
            v_conv_time = GetDataVector(jv + "|", time_vw + "." + dir + "InitCongTime" + period, )
            v_time = if v_conv_time <> null then v_conv_time else v_time
            SetDataVector(jv + "|", llyr + "." + dir + period + "Time", v_time, )
        end
    end
    CloseView(jv)
    CloseView(time_vw)

    // DTWB fields
    v_dtwb = GetDataVector(llyr + "|", "DTWB", )
    set = null
    set.D = if Position(v_dtwb, "D") <> 0 then 1 else 0
    set.T = if Position(v_dtwb, "T") <> 0 then 1 else 0
    set.W = if Position(v_dtwb, "W") <> 0 then 1 else 0
    set.B = if Position(v_dtwb, "B") <> 0 then 1 else 0
    SetDataVectors(llyr + "|", set, )

    // Limit the possible KNR nodes to those with bus stops on them that have drive access
    // Also add drive_node fields for save turns in assignment
    a_fields = {
        {"KNR", "Integer", 10, , , , , "If node can be considered for KNR|(If a bus stop is at the node)"},
        {"drive_node", "Integer", 10, , , , , "If node can be considered for driving|(used for save turns)"}
    }
    RunMacro("Add Fields", {view: nlyr, a_fields: a_fields})
    SetLayer(llyr)
    SelectByQuery("drive_links", "several", "Select * where D = 1")
    SetLayer(nlyr)
    n = SelectByLinks("drive nodes", "several", "drive_links", )
    v = Vector(n, "Long", {Constant: 1})
    SetDataVector(nlyr + "|drive nodes", "drive_node", v, )

    n = SelectByVicinity ("knr", "several", slyr + "|", 10/5280, {"Source And": "drive nodes"})
    v = Vector(n, "Long", {Constant: 1})
    SetDataVector(nlyr + "|knr", "KNR", v, )

    CloseView(ffs_tbl)
    CloseMap(map)

    // Move the cluster field from the TAZ layer to the SE data
    {map, {tlyr}} = RunMacro("Create Map", {file: taz_file})
    se_vw = OpenTable("se", "FFB", {se_file})
    a_fields = {
        {"Cluster", "Integer", 10, , , , , "Cluster definition used in nested DC.|Copied from TAZ layer."},
        {"ClusterName", "Character", 16, , , , , "Cluster definition used in nested DC.|Copied from TAZ layer."}
    }
    RunMacro("Add Fields", {view: se_vw, a_fields: a_fields})
    jv = JoinViews("jv", tlyr + ".ID", se_vw + ".TAZ",)
    v = GetDataVector(jv + "|", tlyr + ".Cluster", )
    SetDataVector(jv + "|", se_vw + ".Cluster", v, )
    v = GetDataVector(jv + "|", tlyr + ".ClusterName", )
    SetDataVector(jv + "|", se_vw + ".ClusterName", v, )
    CloseView(se_vw)
    CloseMap(map)
EndMacro

/*

*/

Macro "Calculate Bus Speeds" (Args)

    csv = Args.[Input Folder] + "\\networks\\bus_speeds.csv"
    link_dbd = Args.Links
    periods = RunMacro("Get Unconverged Periods", Args)
    dirs = {"AB", "BA"}
    modes = {"lb", "eb"}

    eq_vw = OpenTable("bus_eqs", "CSV", {csv})
    {map, {nlyr, llyr}} = RunMacro("Create Map", {file: link_dbd})
    {, , name, ext} = SplitPath(csv)
    a_speed_fields = null
    a_time_fields = null
    for period in periods do
        for dir in dirs do
            for mode in modes do
                a_speed_fields = a_speed_fields + {{
                    dir + period + Upper(mode) + "Speed", "Real", 10, 2, , , ,
                    "The speed " + mode + " travels on the link.|" + 
                    "See " + name + ext + " for details"
                }}
                a_time_fields = a_time_fields + {{
                    dir + period + Upper(mode) + "Time", "Real", 10, 2, , , ,
                    "The time it takes " + mode + " to travel the link.|" + 
                    "See " + name + ext + " for details"
                }}
            end
        end
    end
    RunMacro("Add Fields", {view: llyr, a_fields: a_speed_fields})
    RunMacro("Add Fields", {view: llyr, a_fields: a_time_fields})
    {, eq_specs} = RunMacro("Get Fields", {view_name: eq_vw})
    {, llyr_specs} = RunMacro("Get Fields", {view_name: llyr})
    
    jv = JoinViewsMulti(
        "jv",
        {llyr_specs.HCMType, llyr_specs.AreaType},
        {eq_specs.HCMType, eq_specs.AreaType}, 
    )

    v_length = GetDataVector(jv + "|", llyr_specs.[Length], )
    for period in periods do
        for dir in dirs do
            v_auto_time = GetDataVector(jv + "|", llyr_specs.(dir + period + "Time"), )
            v_bosss = GetDataVector(jv + "|", llyr_specs.("BOSSS"), )
            v_auto_speed = v_length / (v_auto_time / 60)
            for mode in modes do
                v_fac = GetDataVector(jv + "|", eq_specs.(mode + "_fac"), )
                v_speed = v_auto_speed * v_fac
                // For Bus-On-Shoulder System links (BOSS), busses can travel 
                // 15 mph faster than auto traffic using the shoulder, but
                // capped at the speed listed on the link (e.g. 35 mph).
                v_speed = if v_auto_speed < nz(v_bosss) 
                    then min(v_auto_speed + 15, v_bosss) 
                    else v_speed
                v_time = v_length / v_speed * 60
                // handle links without auto times (e.g. transit only)
                v_time = if v_time = null then v_auto_time else v_time
                v_speed = v_length / (v_time / 60)
                data.(llyr_specs.(dir + period + Upper(mode) + "Speed")) = v_speed
                data.(llyr_specs.(dir + period + Upper(mode) + "Time")) = v_time
            end
        end
    end
    SetDataVectors(jv + "|", data, )

    CloseView(jv)
    CloseView(eq_vw)
    CloseMap(map)
endmacro

/*
Creates the various link-based (non-transit) networks. Driving, walking, etc.
*/

Macro "Create Link Networks" (Args)

    link_dbd = Args.Links
    turn_prohibtions = Args.TurnProhibitions
    output_dir = Args.[Output Folder] + "/networks"
    periods = RunMacro("Get Unconverged Periods", Args)

    // Create the auto networks
    // This array could be passed in as an argument to make the function more
    // generic.
    auto_nets = null
    auto_nets.sov.filter = "D = 1 and HOV = 'None'"
    auto_nets.hov.filter = "D = 1"
    for period in periods do
        for i = 1 to auto_nets.length do
            name = auto_nets[i][1]
            
            filter = auto_nets.(name).filter
            net_file = output_dir + "/net_" + period + "_" + name + ".net"

            // Build roadway network
            o = CreateObject("Network.Create")
            o.LayerDB = link_dbd
            o.Filter = filter   
            o.AddLinkField({Name: "FFTime", Field: {"FFTime", "FFTime"}, IsTimeField: true})
            o.AddLinkField({Name: "CongTime", Field: {"AB" + period + "Time", "BA" + period + "Time"}, IsTimeField: true})
            o.AddLinkField({Name: "Capacity", Field: {"AB" + period + "CapE", "BA" + period + "CapE"}, IsTimeField: false})
            o.AddLinkField({Name: "Alpha", Field: "Alpha", IsTimeField: false, DefaultValue: 0.15})
            o.AddLinkField({Name: "Beta", Field: "Beta", IsTimeField: false, DefaultValue: 4.})
            o.AddLinkField({Name: "TollCostSOV", Field: "TollCostSOV", IsTimeField: false})
            o.AddLinkField({Name: "TollCostHOV", Field: "TollCostHOV", IsTimeField: false})
            o.AddLinkField({Name: "TollCostSUT", Field: "TollCostSUT", IsTimeField: false})
            o.AddLinkField({Name: "TollCostMUT", Field: "TollCostMUT", IsTimeField: false})
            if GetFileInfo(turn_prohibtions) <> null then o.TurnProhibitionTable = turn_prohibtions
            o.OutNetworkName = net_file
            o.Run()
            netSetObj = null
            netSetObj = CreateObject("Network.Settings")
            netSetObj.LayerDB = link_dbd
            netSetObj.LoadNetwork(net_file)
            netSetObj.CentroidFilter = "Centroid = 1"
            netSetObj.LinkTollFilter = "TollType = 'Toll'"
            netSetObj.SetPenalties({UTurn: -1})
            netSetObj.Run()
        end
    end

    // Create the non-motorized networks
    nm_nets = null
    nm_nets.walk.filter = "W = 1"
    nm_nets.walk.time_field = "WalkTime"
    nm_nets.bike.filter = "B = 1"
    nm_nets.bike.time_field = "BikeTime"
    for i = 1 to nm_nets.length do
        name = nm_nets[i][1]
        
        filter = nm_nets.(name).filter
        time_field = nm_nets.(name).time_field
        net_file = output_dir + "/net_" + name + ".net"

        o = CreateObject("Network.Create")
        o.LayerDB = link_dbd
        o.Filter =  filter
        o.AddLinkField({Name: time_field, Field: {time_field, time_field}, IsTimeField : true})
        o.NetworkName = net_file
        o.Run()
        netSetObj = null
        netSetObj = CreateObject("Network.Settings")
        netSetObj.LayerDB = link_dbd
        netSetObj.LoadNetwork(net_file)
        netSetObj.CentroidFilter = "Centroid = 1"
        netSetObj.Run()
    end
endmacro

/*
The first time through the model, check the networks by running a 
dummy assignment. This will catch any issues with missing capacities
or speeds.
*/

Macro "Check Highway Networks" (Args)
    feedback_iter = Args.FeedbackIteration
    se_file = Args.SE

    if feedback_iter = 1 then do
        se_vw = OpenTable("se", "FFB", {se_file})
        mtx_file = GetTempFileName(".mtx")
        mh = CreateMatrixFromView("tmep", se_vw + "|", "TAZ", "TAZ", {"TAZ"}, {"File Name": mtx_file})
        mtx = CreateObject("Matrix", mh)
        mtx.AddCores({"SOV"})
        cores = mtx.GetCores()
        cores.SOV := cores.TAZ
        mtx = null
        mh = null
        CloseView(se_vw)
        OtherOpts.od_mtx = mtx_file
        OtherOpts.test = "true"
        OtherOpts.assign_iters = 1
        RunMacro("Run Roadway Assignment", Args, OtherOpts)
    end
endmacro

/*

*/

Macro "Create Route Networks" (Args)

    link_dbd = Args.Links
    rts_file = Args.Routes
    output_dir = Args.[Output Folder] + "/networks"
    periods = RunMacro("Get Unconverged Periods", Args)
    access_modes = Args.access_modes
    TransModeTable = Args.TransModeTable

    // Retag stops to nodes. While this step is done by the route manager
    // during scenario creation, a user might create a new route to test after
    // creating the scenario. This makes sure it 'just works'.
    {map, {rlyr, slyr, , nlyr, llyr}} = RunMacro("Create Map", {file: rts_file})
    TagRouteStopsWithNode(rlyr,,"Node_ID",.2)
    CloseMap(map)

    transit_modes = RunMacro("Get Transit Modes", TransModeTable)
    transit_modes = {"all"} + transit_modes

    for period in periods do
        for transit_mode in transit_modes do

            if transit_mode = "all" 
                then access_mode_subset = {"w"}
                else access_mode_subset = access_modes

            for access_mode in access_mode_subset do
                
                // create transit network .tnw file
                file_name = output_dir + "\\tnet_" + period + "_" + access_mode + "_" + transit_mode + ".tnw"
                o = CreateObject("Network.CreateTransit")
                o.LayerRS = rts_file
                o.OutNetworkName = file_name
                o.StopToNodeTagField = "Node_ID"
                o.RouteFilter = period + "Headway > 0"
                o.IncludeWalkLinks = true
                o.WalkLinkFilter = "W = 1"
                o.AddRouteField({Name: period + "Headway", Field: period + "Headway"})
                o.AddRouteField({Name: "Fare", Field: "Fare"})
                // Add IVTT fields for all modes regardless of which net is being built.
                // The mode table and ModesUsedField will control which are allowed.
                o.AddLinkField({
                    Name: "LBTime",
                    TransitFields: {"AB" + period + "LBTime", "BA" + period + "LBTime"},
                    NonTransitFields: "WalkTime"
                })
                o.AddLinkField({
                    Name: "EBTime",
                    TransitFields: {"AB" + period + "EBTime", "BA" + period + "EBTime"},
                    NonTransitFields: "WalkTime"
                })
                o.AddLinkField({
                    Name: "FGTime",
                    TransitFields: {"AB" + period + "Time", "BA" + period + "Time"},
                    NonTransitFields: "WalkTime"
                })
                o.AddLinkField({
                    Name: "WalkTime",
                    TransitFields: "WalkTime",
                    NonTransitFields: "WalkTime"
                })
                o.AddStopField({Name: "dwell_on", Field: "dwell_on"})
                o.AddStopField({Name: "dwell_off", Field: "dwell_off"})
                o.AddStopField({Name: "xfer_pen", Field: "xfer_pen"})
                o.UseModes({
                    TransitModeField: "Mode",
                    NonTransitModeField: "Mode"
                })
                // Drive attributes for network creation
                if access_mode = "knr" or access_mode = "pnr" then do
                    o.IncludeDriveLinks = true
                    o.DriveLinkFilter = "D = 1"
                    o.AddLinkField({
                        Name: "DriveTime", 
                        TransitFields: {"AB" + period + "Time", "BA" + period + "Time"},
                        NonTransitFields: {"AB" + period + "Time", "BA" + period + "Time"}
                    })
                end
                o.Run()

                // Set transit network settings
                o = CreateObject("Network.SetPublicPathFinder", {RS: rts_file, NetworkName: file_name})
                o.UserClasses = {"Class1"}
                o.CentroidFilter = "Centroid = 1"
                // o.LinkImpedance = "IVTT"
                o.Parameters({
                    MaxTripCost : 240,
                    MaxTransfers : 1,
                    VOT : 0.1984 // $/min (40% of the median wage)
                })
                o.AccessControl({
                    PermitWalkOnly: false,
                    MaxWalkAccessPaths: 10
                })
                o.Combination({CombinationFactor: .1})
                o.StopTimeFields({
                    InitialPenalty: null,
                    //TransferPenalty: "xfer_pen",
                    DwellOn: "dwell_on",
                    DwellOff: "dwell_off"
                })
                o.TimeGlobals({
                    // Headway: 14,
                    InitialPenalty: 0,
                    TransferPenalty: 5,
                    MaxInitialWait: 30,
                    MaxTransferWait: 10,
                    MinInitialWait: 2,
                    MinTransferWait: 5,
                    Layover: 5, 
                    MaxAccessWalk: 45,
                    MaxEgressWalk: 45,
                    MaxModalTotal: 120
                })
                o.RouteTimeFields({Headway: period + "Headway"})
                o.ModeTable({
                    TableName: TransModeTable,
                    // A field in the mode table that contains a list of
                    // link network field names. These network field names
                    // in turn point to the AB/BA fields on the link layer.
                    TimeByMode: "IVTT",
                    ModesUsedField: transit_mode,
                    OnlyCombineSameMode: true,
                    FreeTransfers: 0
                })
                o.RouteWeights({
                    Fare: null,
                    Time: null,
                    InitialPenalty: null,
                    TransferPenalty: null,
                    InitialWait: null,
                    TransferWeight: null,
                    Dwelling: null
                })
                o.GlobalWeights({
                    Fare: 1,
                    Time: 1,
                    InitialPenalty: 1,
                    TransferPenalty: 3,
                    InitialWait: 3,
                    TransferWait: 3,
                    Dwelling: 2,
                    WalkTimeFactor: 3,
                    DriveTimeFactor: 1
                })
                o.Fare({
                    Type: "Flat",
                    RouteFareField: "Fare",
                    RouteXFareField: "Fare",
                    FareValue: 0,
                    TransferFareValue: 0
                })

                // Drive attributes for network settings
                if access_mode = "knr" or access_mode = "pnr" then do
                    o.DriveTime = "DriveTime"
                    opts = null
                    opts.InUse = true
                    opts.PermitAllWalk = false
                    opts.AllowWalkAccess = false
                    if access_mode = "knr" 
                        then opts.ParkingNodes = "KNR = 1"
                        else opts.ParkingNodes = "PNR = 1"
                    if period = "PM" 
                        then o.DriveEgress(opts)
                        else o.DriveAccess(opts)
                end
                ok = o.Run()
                o = null
            end
        end
    end
endmacro