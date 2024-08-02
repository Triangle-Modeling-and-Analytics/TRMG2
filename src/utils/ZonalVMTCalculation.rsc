Macro "Open Zonal VMT Calculation Dbox" (Args)
	RunDbox("Zonal VMT Calculation", Args)
endmacro

dBox "Zonal VMT Calculation" (Args) center, center, 60, 10 
    Title: "Zonal VMT Comparison Tool" Help: "test" toolbox NoKeyBoard

    close do
        return()
    enditem

    init do
        static S2_Dir, S1_Dir, S1_Name, Scen_Dir
    
        Scen_Dir = Args.[Scenarios Folder]
        S1_Dir = Args.[Scenario Folder]
        S1_Name = Substitute(S1_Dir, Scen_Dir + "\\", "",)

    enditem

    // Old/base Scenario directory
    text 5, 1 variable: "Old/Base Scenario Directory:"
    text same, after, 40 variable: S2_Dir framed
    button after, same, 6 Prompt: "..." do

        on escape goto nodir
        S2_Dir = ChooseDirectory("Choose the old/base scenario directory:", )

        nodir:
        on error, notfound, escape default
     enditem 

    // New Scenario
    Text 38, 5, 15 Prompt: "New Scenario (selected in scenario list):" Variable: S1_Name

    // Quit Button
    button 5, 8, 10 Prompt:"Quit" do
        Return(1)
    enditem

    // Run Button
    button 18, 8, 20 Prompt:"Generate Results" do 

        if !RunMacro("Zonal VMT Calculation", Args, S2_Dir, TOD) then Throw("Something went wrong")
 
        ShowMessage("Reports have been created successfully.")
	return(1)
	
    exit:	
        showmessage("Something is wrong")	
        return(0)
    Enditem

    Button 41, 8, 10 Prompt: "Help" do
        ShowMessage(
        "This tool is used to calculate zonal VMT difference on the production end between two scenarios. " +
         "Instead of using network VMT, this tool uses auto trip matrix and distance skim to capture " +
         "zonal VMT genearted at the production end. "
     )
    enditem
enddbox

Macro "Zonal VMT Calculation" (Args, S2_Dir)
    S1_Dir = Args.[Scenario Folder]
    TOD_list = Args.Periods
    taz_file = Args.TAZs
    S1_se_file = Args.[Input SE]
    S2_se_file = S2_Dir + "\\input\\sedata\\scenario_se.bin"
    reporting_dir = S1_Dir + "\\output\\_summaries"
    output_dir = reporting_dir + "\\Zonal_VMT_Comparison"
    //if GetDirectoryInfo(output_dir, "All") <> null then PutInRecycleBin(output_dir)
    RunMacro("Create Directory", output_dir)
    
    // Get scenario names
    scen_Dirs = {S1_Dir, S2_Dir}
    comp_string = null
    
    parts = ParseString(S1_Dir, "\\")
    s1_name = parts[parts.length] 
    parts = ParseString(S2_Dir, "\\")
    s2_name = parts[parts.length]
    comp_string = s1_name + "_" + s2_name
    

    // Loop through scenarios and run VMT tool for each scenario
    for dir in scen_Dirs do
        opts = null
        opts.[Scenario Folder] = dir
        opts.Periods = {"AM", "MD", "PM", "NT"}
        opts.TAZs = dir + "\\output\\tazs\\scenario_tazs.dbd"
        opts.[Input SE] = dir + "\\input\\sedata\\scenario_se.bin"
        opts.HBHOV3OccFactors = dir + "\\input\\resident\\tod\\hov3_occ_factors_hb.csv"
        RunMacro("Calculate Zone VMT", opts) 
    end
    
    // Join vmt tables
    s1_vmt_df = CreateObject("df", S1_Dir + "\\output\\_summaries\\Zonal_VMT_Comparison\\Zone_VMT.csv")
    s2_vmt_df = CreateObject("df", S2_Dir + "\\output\\_summaries\\Zonal_VMT_Comparison\\Zone_VMT.csv")
    s1_vmt_df.left_join(s2_vmt_df, "TAZ", "TAZ")
    names = s1_vmt_df.colnames()
    for name in names do
        if right(name, 2) = "_x" then do
            new_name = Substitute(name, "_x", "_" + s1_name, 1)
            s1_vmt_df.rename(name, new_name)
        end
        else if right(name, 2) = "_y" then do
            new_name = Substitute(name, "_y", "_" + s2_name, 1)
            s1_vmt_df.rename(name, new_name)
        end 
    end
    
    // Calculate VMT delta
    s1_vmt_df.mutate("TotalVMT_perser_delta", nz(s1_vmt_df.tbl.("TotalVMT_perser_" + s1_name)) - nz(s1_vmt_df.tbl.("TotalVMT_perser_" + s2_name)))
    s1_vmt_df.mutate("HBVMT_perres_delta", nz(s1_vmt_df.tbl.("HBVMT_perres_" + s1_name)) - nz(s1_vmt_df.tbl.("HBVMT_perres_" + s2_name)))
    s1_vmt_df.mutate("HBWVMT_peremp_delta", nz(s1_vmt_df.tbl.("HBWVMT_peremp_" + s1_name)) - nz(s1_vmt_df.tbl.("HBWVMT_peremp_" + s2_name)))
    s1_vmt_df.write_bin(output_dir + "/Comparison_zonalVMT.bin")
    s1_vmt_df.write_csv(output_dir + "/Comparison_zonalVMT.csv")

    // Mapping VMT delta on a taz map
    vw = OpenTable("vw", "FFB", {output_dir + "/Comparison_zonalVMT.bin"})
    mapFile = output_dir + "/" + comp_string + "Comparison_ZonalVMT.map"
    {map, {tlyr}} = RunMacro("Create Map", {file: taz_file})
    jnvw = JoinViews("jv", tlyr + ".ID", vw + ".TAZ",)
    SetView(jnvw)

    // Create a theme for the travel time difference
    numClasses = 4
    opts = null
    opts.[Pretty Values] = "True"
    opts.[Drop Empty Classes] = "True"
    opts.Title = "by production zone "
    opts.Other = "False"
    opts.[Force Value] = 0
    opts.zero = "TRUE"

    cTheme = CreateTheme("ZonalVMT", jnvw+".TotalVMT_perser_delta", "Equal Steps" , numClasses, opts)

    // Set theme fill color and style
    opts = null
    a_color = {
        ColorRGB(65535, 65535, 54248),
        ColorRGB(41377, 56026, 46260),
        ColorRGB(16705, 46774, 50372),
        ColorRGB(8738, 24158, 43176)
    }
    SetThemeFillColors(cTheme, a_color)
    str1 = "XXXXXXXX"
    solid = FillStyle({str1, str1, str1, str1, str1, str1, str1, str1})
    for i = 1 to numClasses do
      a_fillstyles = a_fillstyles + {solid}
    end
    SetThemeFillStyles(cTheme, a_fillstyles)
    ShowTheme(, cTheme)

    // Modify the border color
    lightGray = ColorRGB(45000, 45000, 45000)
    SetLineColor(, lightGray)

    cls_labels = GetThemeClassLabels(cTheme)
    for i = 1 to cls_labels.length do
      label = cls_labels[i]
    end
    SetThemeClassLabels(cTheme, cls_labels)

    // Configure Legend
    SetLegendDisplayStatus(cTheme, "True")
    RunMacro("G30 create legend", "Theme")
    title = "Change in Total VMT per Service Population"
    footnote = comp_string + "_comparison"
    SetLegendSettings (
      GetMap(),
      {
        "Automatic",
        {0, 1, 0, 0, 1, 4, 0},
        {1, 1, 1},
        {"Arial|Bold|14", "Arial|9", "Arial|Bold|12", "Arial|12"},
        {title, footnote}
      }
    )
    SetLegendOptions (GetMap(), {{"Background Style", solid}})

    RedrawMap(map)
    SaveMap(map,mapFile)
    CloseMap(map)

    // Close everything
    RunMacro("Close All")
    out_mtx = null
    auto_mtx = null
    skim_mtx = null
    out_cores = null
    auto_cores = null
    skim_cores = null
    DeleteFile(out_file)
    DeleteFile(Substitute(vmt_binfile, ".bin", ".DCB",))
    DeleteFile(vmt_binfile)

    Return(1)

endmacro

Macro "Calculate Zone VMT" (Args)
    dir = Args.[Scenario Folder]
    TOD_list = Args.Periods
    taz_file = Args.TAZs
    se_file = Args.[Input SE]
    factor_file = Args.HBHOV3OccFactors
    skim_dir = dir + "\\output\\skims\\roadway"
    autotrip_dir = dir + "\\output\\_summaries\\resident_hb"
    reporting_dir = dir + "\\output\\_summaries"
    output_dir = reporting_dir + "\\Zonal_VMT_Comparison"
    RunMacro("Create Directory", output_dir)

    // 0. create output matrix
    out_file = output_dir + "\\Zone_VMT.mtx"
    autotrip = autotrip_dir + "\\pa_veh_trips_AM.mtx"
    CopyFile(autotrip, out_file)
    out_mtx = CreateObject("Matrix", out_file)
    out_core_names = out_mtx.GetCoreNames()
    out_mtx.AddCores({"HB_VMT"})
    out_mtx.DropCores(out_core_names)

    // 0. Create the output table (first iteration only)
    vmt_binfile = output_dir + "\\Zone_VMT.bin"
    if GetFileInfo(vmt_binfile) <> null then do
        DeleteFile(vmt_binfile)
        DeleteFile(Substitute(vmt_binfile, ".bin", ".dcb", ))
    end
    out_vw = CreateTable("out", vmt_binfile, "FFB", {
        {"TAZ", "Integer", 10, , , "Zone ID"}
    })
    se_vw = OpenTable("se", "FFB", {se_file})
    taz = GetDataVector(se_vw + "|", "TAZ", )
    n = GetRecordCount(se_vw, )
    AddRecords(out_vw, , , {"empty records": n})
    SetDataVector(out_vw + "|", "TAZ", taz, )
    CloseView(se_vw)
    CloseView(out_vw)

    // 1. Calculate home based VMT per resident
    // 1.1 Loop through TOD to calculate HB VMT
    field_name = "HB_VMT"
    fields_to_add = fields_to_add + {{field_name, "Real", 10, 2,,,, desc}}
    
    out_core = out_mtx.GetCore("HB_VMT")
    mode = {"sov", "hov2", "hov3"}
    for tod in TOD_list do
        // set input path
        trip_file = autotrip_dir + "\\pa_veh_trips_" + tod + ".mtx"
        trip_mtx = CreateObject("Matrix", trip_file)
        trip_cores = trip_mtx.GetCores()

        skim_sov_file = skim_dir + "\\skim_sov_" + tod + ".mtx"
        skim_hov_file = skim_dir + "\\skim_hov_" + tod + ".mtx"
        skim_sov_mtx = CreateObject("Matrix", skim_sov_file)
        skim_hov_mtx = CreateObject("Matrix", skim_hov_file)
        skim_sov_core = skim_sov_mtx.GetCore("Length (Skim)")
        skim_hov_core = skim_hov_mtx.GetCore("Length (Skim)")

        out_core := nz(out_core) + nz(trip_cores.("sov")) * nz(skim_sov_core) + nz(trip_cores.("hov2")) * nz(skim_hov_core) +  nz(trip_cores.("hov3")) * nz(skim_hov_core)
    end
    v_hbvmt = out_mtx.GetVector({"Core": "HB_VMT", Marginal: "Row Sum"})
    v_hbvmt.rowbased = "true"
    data.(field_name) = nz(v_hbvmt)

    // 2. Calculate total VMT per service population
    // 2.1 Calculate IEEI VMT
    field_name = "IEEI_VMT"
    fields_to_add = fields_to_add + {{field_name, "Real", 10, 2,,,, desc}}

    out_mtx.AddCores({"IEEI_VMT"})
    out_core = out_mtx.GetCore("IEEI_VMT")

    IEEI_dir = dir + "\\output\\external"
    IEEI_trip = IEEI_dir + "\\ie_od_trips.mtx"
    trip_mtx = CreateObject("Matrix", IEEI_trip)
    trip_cores = trip_mtx.GetCores()
    core_names = trip_mtx.GetCoreNames()
      
    skim_file = skim_dir + "\\accessibility_sov_AM.mtx"
    skim_mtx = CreateObject("Matrix", skim_file)
    skim_core = skim_sov_mtx.GetCore("Length (Skim)")

    for core_name in core_names do
        out_core := nz(out_core) + nz(skim_core) * nz(trip_cores.(core_name))
    end

    v_ieeivmt = out_mtx.GetVector({"Core": "IEEI_VMT", Marginal: "Row Sum"})
    v_ieeivmt.rowbased = "true"
    data.(field_name) = nz(v_ieeivmt)

    // 2.2 Calculate University VMT
    field_name = "University_VMT"
    fields_to_add = fields_to_add + {{field_name, "Real", 10, 2,,,, desc}}

    out_mtx.AddCores({"University_VMT"})
    out_core = out_mtx.GetCore("University_VMT")

    univ_dir = dir + "\\output\\university"
    for tod in TOD_list do
        // set input path
        univ_trip = univ_dir + "\\mode\\university_pa_modal_trips_" + tod + ".mtx"
        univ_mtx = CreateObject("Matrix", univ_trip)
        univ_core = univ_mtx.GetCore("auto")

        skim_file =  skim_dir + "\\skim_sov_" + tod + ".mtx"
        skim_mtx = CreateObject("Matrix", skim_file)
        skim_core = skim_sov_mtx.GetCore("Length (Skim)")

        out_core := nz(out_core) + nz(skim_core) * nz(univ_core)      
    end

    v_univvmt = out_mtx.GetVector({"Core": "University_VMT", Marginal: "Row Sum"})
    v_univvmt.rowbased = "true"
    data.(field_name) = nz(v_univvmt)

    // 3. Calculate home base work VMT
    field_name = "HBW_VMT"
    fields_to_add = fields_to_add + {{field_name, "Real", 10, 2,,,, desc}}

    RunMacro("Create HBW PA Vehicle Trip Matrices", Args)
    out_mtx.AddCores({"HBW_VMT"})
    out_core = out_mtx.GetCore("HBW_VMT")

    // 3.2 Loop through TOD to calculate HBW VMT
    mode = {"sov", "hov2", "hov3"}
    for tod in TOD_list do
        // set input path
        trip_file = output_dir + "\\pa_veh_trips_W_HB_W_All_" + tod + ".mtx"
        trip_mtx = CreateObject("Matrix", trip_file)
        trip_cores = trip_mtx.GetCores()

        skim_sov_file = skim_dir + "\\skim_sov_" + tod + ".mtx"
        skim_hov_file = skim_dir + "\\skim_hov_" + tod + ".mtx"
        skim_sov_mtx = CreateObject("Matrix", skim_sov_file)
        skim_hov_mtx = CreateObject("Matrix", skim_hov_file)
        skim_sov_core = skim_sov_mtx.GetCore("Length (Skim)")
        skim_hov_core = skim_hov_mtx.GetCore("Length (Skim)")

        out_core := nz(out_core) + nz(trip_cores.("sov")) * nz(skim_sov_core) + nz(trip_cores.("hov2")) * nz(skim_hov_core) +  nz(trip_cores.("hov3")) * nz(skim_hov_core)
        trip_mtx = null
        trip_cores = null
    end

    v_hbwvmt = out_mtx.GetVector({"Core": "HBW_VMT", Marginal: "Column Sum"})
    v_hbwvmt.rowbased = "true"
    data.(field_name) = nz(v_hbwvmt)
    
    // Fill in the raw output table
    out_vw = OpenTable("out", "FFB", {vmt_binfile})
    RunMacro("Add Fields", {view: out_vw, a_fields: fields_to_add})
    SetDataVectors(out_vw + "|", data, )
    CloseView(out_vw)

    // Join SE data
    vmt_df = CreateObject("df", vmt_binfile)
    se_df = CreateObject("df", se_file)
    vmt_df.left_join(se_df, "TAZ", "TAZ")
    vmt_df.mutate("Emp", vmt_df.tbl.("Industry") + vmt_df.tbl.("Retail") + vmt_df.tbl.("Service_RateHigh") + vmt_df.tbl.("Service_RateLow") + vmt_df.tbl.("Office"))
    vmt_df.mutate("Student", vmt_df.tbl.("StudGQ_NCSU") + vmt_df.tbl.("StudGQ_UNC") + vmt_df.tbl.("StudGQ_DUKE") + vmt_df.tbl.("StudGQ_NCCU"))
    vmt_df.mutate("ServicePopulation", vmt_df.tbl.("HH_POP") + vmt_df.tbl.("Emp") + vmt_df.tbl.("Student"))
    vmt_df.mutate("TotalVMT_perser", (vmt_df.tbl.("HB_VMT")  + vmt_df.tbl.("IEEI_VMT") + vmt_df.tbl.("University_VMT"))/vmt_df.tbl.("ServicePopulation"))
    vmt_df.mutate("HBVMT_perres", vmt_df.tbl.("HB_VMT")/vmt_df.tbl.("HH_POP"))
    vmt_df.mutate("HBWVMT_peremp", vmt_df.tbl.("HBW_VMT")/vmt_df.tbl.("Emp"))
    vmt_df.rename("HH_POP", "Res")
    vmt_df.select({"TAZ", "HB_VMT", "University_VMT", "IEEI_VMT", "HBW_VMT", "Res", "Emp", "Student", "ServicePopulation", "TotalVMT_perser", "HBVMT_perres", "HBWVMT_peremp"})
    vmt_df.write_csv(output_dir + "/Zone_VMT.csv")

        // Delete interim files
    DeleteFile(vmt_binfile)
    DeleteFile(Substitute(vmt_binfile, ".bin", ".dcb",))
    for tod in TOD_list do
        // set input path
        trip_file = output_dir + "\\pa_veh_trips_W_HB_W_All_" + tod + ".mtx"
        DeleteFile(trip_file)
    end
    Return(1)  

    Return(1)    
endmacro

Macro "Create HBW PA Vehicle Trip Matrices" (Args)

    // This section is a slight modification to the "HB Occupancy" macro
    factor_file = Args.HBHOV3OccFactors
    periods = Args.periods
    trip_dir = Args.[Scenario Folder] + "\\output\\resident\\trip_matrices"
    output_dir = Args.[Scenario Folder] + "\\output\\_summaries\\Zonal_VMT_Comparison"

    fac_vw = OpenTable("factors", "CSV", {factor_file})
    
    rh = GetFirstRecord(fac_vw + "|", )
    while rh <> null do
        trip_type = fac_vw.trip_type
        period = fac_vw.tod
        if trip_type <> "W_HB_W_All" then goto skip // only do for work trip
        if periods.position(period) = 0 then goto skip
        hov3_factor = fac_vw.hov3

        per_mtx_file = trip_dir + "/pa_per_trips_W_HB_W_All_" + period + ".mtx"
        veh_mtx_file = output_dir + "/pa_veh_trips_W_HB_W_All_" + period + ".mtx"
        CopyFile(per_mtx_file, veh_mtx_file)
        mtx = CreateObject("Matrix", veh_mtx_file)
        cores = mtx.GetCores()
        cores.hov2 := cores.hov2 / 2
        cores.hov3 := cores.hov3 / hov3_factor

        skip:
        rh = GetNextRecord(fac_vw + "|", rh, )
    end
    CloseView(fac_vw)
endmacro