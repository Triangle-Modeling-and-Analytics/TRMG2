/*
Handle initial steps like capacity and speed calculations.
*/

Macro "Initial Processing" (Args)
    
    RunMacro("Create Output Copies", Args)
    RunMacro("Determine Area Type", Args)
    RunMacro("Capacity", Args)
    RunMacro("Set CC Speeds", Args)
    RunMacro("Other Attributes", Args)
    RunMacro("Calculate Bus Speeds", Args)
    RunMacro("Create Link Networks", Args)
    RunMacro("Create Route Networks", Args)

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
        a_ft_priority = {"Freeway", "Arterial", "Collector", "Superstreet", "MLHighway", "TLHighway"}
        RunMacro("Assign FT to Ramps", link_lyr, node_lyr, ramp_query, fac_field, a_ft_priority)
    end

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
    periods = Args.periods
    trans_ratio_auto = Args.TransponderRatioAuto
    trans_ratio_sut = Args.TransponderRatioSUT
    trans_ratio_mut = Args.TransponderRatioMUT

    {map, {rlyr, slyr, , nlyr, llyr}} = RunMacro("Create Map", {file: rts_file})
    
    a_fields = {
        {"TollCostSOV", "Real", 10, 2, , , , "AutoTollRate * Length|Influenced by TransponderRatioAuto"},
        {"TollCostHOV", "Real", 10, 2, , , , "Same as TollCostSOV, but HOT lanes are free."},
        {"TollCostSUT", "Real", 10, 2, , , , "SUTTollRate * Length * 2|Influenced by TransponderRatioSUT"},
        {"TollCostMUT", "Real", 10, 2, , , , "MUTTollRate * Length * 4|Influenced by TransponderRatioMUT"},
        {"D", "Integer", 10, , , , , "If drive mode is allowed (from DTWB column)"},
        {"T", "Integer", 10, , , , , "If transit mode is allowed (from DTWB column)"},
        {"W", "Integer", 10, , , , , "If walk mode is allowed (from DTWB column)"},
        {"B", "Integer", 10, , , , , "If bike mode is allowed (from DTWB column)"},
        {"Alpha", "Real", 10, 2, , , , "VDF alpha value"},
        {"Beta", "Real", 10, 2, , , , "VDF beta value"},
        {"WalkTime", "Real", 10, 2, , , , "Length / 3 mph"},
        {"BikeTime", "Real", 10, 2, , , , "Length / 15 mph"},
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
    {v_dir, v_type, v_len, v_ps, v_tolltype, v_tollrate_t, v_tollrate_nt, v_mod, v_alpha, v_beta} = GetDataVectors(
        jv + "|", {
            llyr + ".Dir",
            llyr + ".HCMType",
            llyr + ".Length",
            llyr + ".PostedSpeed",
            llyr + ".TollType",
            llyr + ".TollRateT",
            llyr + ".TollRateNT",
            ffs_tbl + ".ModifyPosted",
            ffs_tbl + ".Alpha",
            ffs_tbl + ".Beta"
            },
        )
    v_ffs = v_ps + v_mod
    v_fft = v_len / v_ffs * 60
    v_wt = v_len / 3 * 60
    v_bt = v_len / 15 * 60
    v_mode = Vector(v_wt.length, "Integer", {Constant: 1})
    // Determine weighted average toll rate based on transponder usage
    v_tollrate_auto = v_tollrate_t * trans_ratio_auto + v_tollrate_nt * (1 - trans_ratio_auto)
    v_tollrate_sut = v_tollrate_t * trans_ratio_sut + v_tollrate_nt * (1 - trans_ratio_sut)
    v_tollrate_mut = v_tollrate_t * trans_ratio_mut + v_tollrate_nt * (1 - trans_ratio_mut)
    v_tollcost_auto = v_tollrate_auto * v_len
    v_tollcost_sut = v_tollrate_sut * v_len * 2
    v_tollcost_mut = v_tollrate_mut * v_len * 4
    v_tollcost_hot = if v_tolltype = "HOT" then 0 else v_tollcost_auto
    SetDataVector(jv + "|", llyr + ".FFSpeed", v_ffs, )
    SetDataVector(jv + "|", llyr + ".FFTime", v_fft, )
    SetDataVector(jv + "|", llyr + ".Alpha", v_alpha, )
    SetDataVector(jv + "|", llyr + ".Beta", v_beta, )
    SetDataVector(jv + "|", llyr + ".WalkTime", v_wt, )
    SetDataVector(jv + "|", llyr + ".BikeTime", v_bt, )
    SetDataVector(jv + "|", llyr + ".Mode", v_mode, )
    SetDataVector(jv + "|", llyr + ".TollCostSOV", v_tollcost_auto, )
    SetDataVector(jv + "|", llyr + ".TollCostHOV", v_tollcost_hot, )
    SetDataVector(jv + "|", llyr + ".TollCostSUT", v_tollcost_sut, )
    SetDataVector(jv + "|", llyr + ".TollCostMUT", v_tollcost_mut, )
    v_ab_time = if v_dir = 1 or v_dir = 0 then v_fft
    v_ba_time = if v_dir = -1 or v_dir = 0 then v_fft
    for period in periods do
        SetDataVector(jv + "|", llyr + ".AB" + period + "Time", v_ab_time, )
        SetDataVector(jv + "|", llyr + ".BA" + period + "Time", v_ba_time, )
    end
    CloseView(jv)

    // DTWB fields
    v_dtwb = GetDataVector(llyr + "|", "DTWB", )
    set = null
    set.D = if Position(v_dtwb, "D") <> 0 then 1 else 0
    set.T = if Position(v_dtwb, "T") <> 0 then 1 else 0
    set.W = if Position(v_dtwb, "W") <> 0 then 1 else 0
    set.B = if Position(v_dtwb, "B") <> 0 then 1 else 0
    SetDataVectors(llyr + "|", set, )

    // Limit the possible KNR nodes to those with bus stops on them
    a_fields = {
        {"KNR", "Integer", 10, , , , , "If node can be considered for KNR|(If a bus stop is at the node)"}
    }
    RunMacro("Add Fields", {view: nlyr, a_fields: a_fields})
    SetLayer(nlyr)
    n = SelectByVicinity ("knr", "several", slyr + "|", 10/5280)
    v = Vector(n, "Long", {Constant: 1})
    SetDataVector(nlyr + "|knr", "KNR", v, )

    CloseView(ffs_tbl)
    CloseMap(map)
EndMacro

/*

*/

Macro "Calculate Bus Speeds" (Args)

    csv = Args.[Input Folder] + "\\networks\\bus_speeds.csv"
    link_dbd = Args.Links
    periods = Args.periods
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
    CloseMap(map)
endmacro

/*
Creates the various link-based (non-transit) networks. Driving, walking, etc.
*/

Macro "Create Link Networks" (Args)

    link_dbd = Args.Links
    output_dir = Args.[Output Folder] + "/networks"
    periods = Args.periods

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
            o.NetworkName = net_file
            o.Run()
            netSetObj = null
            netSetObj = CreateObject("Network.Settings")
            netSetObj.LayerDB = link_dbd
            netSetObj.LoadNetwork(net_file)
            netSetObj.CentroidFilter = "Centroid = 1"
            netSetObj.LinkTollFilter = "TollType = 'Toll'"
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

*/

Macro "Create Route Networks" (Args)

    link_dbd = Args.Links
    rts_file = Args.Routes
    output_dir = Args.[Output Folder] + "/networks"
    periods = Args.periods
    access_modes = Args.access_modes
    TransModeTable = Args.TransModeTable

    transit_modes = RunMacro("Get Transit Modes", TransModeTable)

    for period in periods do
        for transit_mode in transit_modes do

            // Busses use the bus speed equations, but rail/brt will use
            // auto times + stop dwell times.
            if transit_mode = "lb" or transit_mode = "eb" 
                then use_dwell = "false"
                else use_dwell = "true"

            for access_mode in access_modes do
                
                // create transit network .tnw file
                file_name = output_dir + "\\tnet_" + period + "_" + access_mode + "_" + transit_mode + ".tnw"
                o = CreateObject("Network.CreateTransit")
                o.LayerRS = rts_file
                o.NetworkName = file_name
                o.StopToNodeTagField = "Node_ID"
                o.RouteFilter = period + "Headway > 0"
                o.IncludeWalkLinks = true
                o.WalkLinkFilter = "W = 1"
                o.AddRouteField({Name: period + "Headway", Field: period + "Headway"})
                o.AddRouteField({Name: "Fare", Field: "Fare"})
                if use_dwell then suffix = "Time" else suffix = Upper(transit_mode) + "Time"
                o.AddLinkField({
                    Name: "IVTT", 
                    TransitFields: {"AB" + period + suffix, "BA" + period + suffix}, 
                    NonTransitFields: {"WalkTime", "WalkTime"}
                })
                if use_dwell then do
                    o.AddStopField({Name: "dwell_on", Field: "dwell_on"})
                    o.AddStopField({Name: "dwell_off", Field: "dwell_off"})
                end
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
                o.LinkImpedance = "IVTT"
                o.Parameters({
                    MaxTripCost = 999,
                    MaxTransfers = 4,
                    VOT = .1984 // $/min (40% of the median wage)
                })
                o.AccessControl({PermitWalkOnly: false})
                o.Combination({CombinationFactor: .1})
                stop_time_opts = {
                    InitialPenalty: null,
                    TransferPenalty: "xfer_pen"
                }
                time_global_opts = {
                    Headway: 14,
                    InitialPenalty: 0,
                    TransferPenalty: 3,
                    MaxInitialWait: 20,
                    MaxTransferWait: 10,
                    MinInitialWait: 2,
                    MinTransferWait: 2,
                    Layover: 5, 
                    MaxAccessWalk: 45,
                    MaxEgressWalk: 45,
                    MaxModalTotal: 240
                }
                if use_dwell then do
                    stop_time_opts = stop_time_opts + {
                        DwellOn: "dwell_on",
                        DwellOff: "dwell_off"
                    }
                    if transit_mode = "brt"
                        then dwell_time = 1 // 1 minute stop time brt assumption
                        else dwell_time = 5 // 5 minute stop time rail assumption
                    time_global_opts = time_global_opts + {
                        DwellOn: dwell_time / 2,
                        DwellOff: dwell_time / 2
                    }
                end else do
                    time_global_opts = time_global_opts + {
                        DwellOn: 0,
                        DwellOff: 0
                    }
                end
                o.StopTimeFields(stop_time_opts)
                o.TimeGlobals(time_global_opts)
                o.RouteTimeFields({Headway: period + "Headway"})
                o.ModeTable({
                    TableName: TransModeTable,
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
                    TransferPenalty: 1,
                    InitialWait: 2,
                    TransferWeight: 2,
                    Dwelling: 2,
                    WalkTimeFactor: 3,
                    DriveTimeFactor: 0
                })
                o.Fare({
                    Type: "Flat",
                    RouteFareField: "Fare",
                    RouteXFareField: "Fare"
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