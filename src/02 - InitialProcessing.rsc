/*
Handle initial steps like capacity and speed calculations.
*/

Macro "Initial Processing" (Args)
    
    RunMacro("Create Output Copies", Args)
    RunMacro("Determine Area Type", Args)
    RunMacro("Capacity", Args)
    // RunMacro("Set CC Speeds", Args)
    // RunMacro("Other Attributes", Args)
    // RunMacro("Filter Transit Settings", Args)

    return(1)
EndMacro

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
        {"Density", "Real", 10, 2,,,, "Density"},
        {"AreaType", "Character", 10,,,,, "Area Type"},
        {"ATSmoothed", "Integer", 10,,,,, "Whether or not the area type was smoothed"}
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
        {OptArray: TRUE}
    )
    tot_emp = data.Industry + data.Office + data.Service_RateLow + 
        data.Service_RateHigh + data.Retail
    factor = data.HH_POP.sum() / tot_emp.sum()
    density = (data.HH_POP + tot_emp * factor) / data.area
    areatype = Vector(density.length, "String", )
    for i = 1 to area_tbl.length do
        name = area_tbl[i].AreaType
        cutoff = area_tbl[i].Density
        areatype = if density >= cutoff then name else areatype
    end
    SetDataVector(jv + "|", "TotalEmp", tot_emp, )
    SetDataVector(jv + "|", se_vw + ".Density", density, )
    SetDataVector(jv + "|", se_vw + ".AreaType", areatype, )

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
    SelectByQuery("primary", "several", "Select * where PrimaryLink = 1")

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
    query = "Select * where AreaType = null and PrimaryLink = 1"
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
        "LOS E capacity per hour per lane|LOS E is used for assignment."},
        {"MLHighway", "Integer", 10, ,,,, "If road is a rural multi-lane highway"},
        {"TLHighway", "Integer", 10, ,,,, "If road is a rural two-lane highway"}
    }
    RunMacro("Add Fields", {view: link_lyr, a_fields: a_fields})
    {link_fields, link_specs} = RunMacro("Get Fields", {view_name: link_lyr})

    // Assign facility type to ramps
    ramp_query = "Select * where HCMType = 'Ramp'"
    fac_field = "HCMType"
    a_ft_priority = {"Freeway", "Arterial", "Collector"}
    RunMacro("Assign FT to Ramps", link_lyr, node_lyr, ramp_query, fac_field, a_ft_priority)

    // Update area type to identify ML and TL rural highways
    data = GetDataVectors(
        link_lyr + "|",
        {"HCMType", "AreaType", "ABLanes", "BALanes", "Dir"},
        {OptArray: TRUE}
    )
    lanes = nz(data.ABLanes) + nz(data.BALanes)
    type = if lanes = 0 then ""
        else if data.HCMType = "Freeway" then ""
        else if data.HCMType = "Superstreet" then ""
        else if data.AreaType <> "Rural" then ""
        else if lanes = 2 and data.Dir = 0 then "TL"
        else "ML"
    orig_areatype = data.AreaType
    new_areatype = data.AreaType + type
    ml_flag = if type = "ML" then 1 else null
    tl_flag = if type = "TL" then 1 else null
    SetDataVector(link_lyr + "|", "AreaType", new_areatype, )
    SetDataVector(link_lyr + "|", "MLHighway", ml_flag, )
    SetDataVector(link_lyr + "|", "TLHighway", tl_flag, )

    // Add hourly capacity to link layer
    cap_vw = OpenTable("cap", "CSV", {cap_file})
    {cap_fields, cap_specs} = RunMacro("Get Fields", {view_name: cap_vw})
    jv = JoinViewsMulti(
        "jv", 
        {link_specs.HCMType, link_specs.AreaType},
        {cap_specs.HCMType, cap_specs.AreaType},
        null
    )
    hcm_type = GetDataVector(jv + "|", link_specs.HCMType, )
    hcm_med = GetDataVector(jv + "|", link_specs.HCMMedian, )
    boost = if hcm_type = "Freeway" then 1
        else if hcm_type = "Superstreet" then 1
        else if hcm_med = "NonRestrictive" then 1.04
        else if hcm_med = "Restrictive" then 1.08
        else 1
    capd = GetDataVector(jv + "|", cap_specs.capd_phpl, )
    cape = GetDataVector(jv + "|", cap_specs.cape_phpl, )
    capd = capd * boost
    cape = cape * boost
    SetDataVector(jv + "|", link_specs.capd_phpl, capd, )
    SetDataVector(jv + "|", link_specs.cape_phpl, cape, )
    CloseView(jv)
    CloseView(cap_vw)
    // Reset area type field to original (without "ML"/"TL")
    SetDataVector(link_lyr + "|", "AreaType", orig_areatype, )

    // Determine period capacities
    factor_vw = OpenTable("factors", "CSV", {capfactors_file})
    {fac_fields, fac_specs} = RunMacro("Get Fields", {view_name: factor_vw})
    v_periods = GetDataVector(factor_vw + "|", "TOD", )
    v_factors = GetDataVector(factor_vw + "|", "Value", )
    a_los = {"D", "E"}
    a_dir = {"AB", "BA"}
    for los in a_los do
        for i = 1 to v_periods.length do
            period = v_periods[i]
            factor = v_factors[i]
        
            for dir in a_dir do
                field_name = dir + period + "Cap" + los
                a_fields = {
                    {field_name, "Integer", 10,,,,, "hourly los " + los + " capacity per lane"}
                }
                RunMacro("Add Fields", {view: link_lyr, a_fields: a_fields})

                v_hourly = GetDataVector(link_lyr + "|", "cap" + Lower(los) + "_phpl", )
                v_lanes = GetDataVector(link_lyr + "|", dir + "Lanes", )
                v_period = v_hourly * factor * v_lanes
                SetDataVector(link_lyr + "|", field_name, v_period, )
            end
        end
    end

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