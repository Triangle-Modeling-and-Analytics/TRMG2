/*
Handle initial steps like capacity and speed calculations.
*/

Macro "Initial Processing" (Args)
    
    RunMacro("Create Output Copies", Args)
    RunMacro("Determine Area Type", Args)
    // RunMacro("Capacity", Args)
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