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
    

    // Loop through scenarios and run TIA for each scenario
    for dir in scen_Dirs do
        opts = null
        opts.[Scenario Folder] = dir
        opts.Periods = {"AM", "MD", "PM", "NT"}
        opts.TAZs = dir + "\\output\\tazs\\scenario_tazs.dbd"
        opts.[Input SE] = dir + "\\input\\sedata\\scenario_se.bin"
        opts.HBHOV3OccFactors = dir + "\\input\\resident\\tod\\hov3_occ_factors_hb.csv"
        opts.skim_dir = dir + "\\output\\skims\\roadway"
        opts.autotrip_dir = dir + "\\output\\_summaries\\resident_hb"
        opts.reporting_dir = dir + "\\output\\_summaries"
        opts.output_dir = dir + "\\output\\_summaries\\VMT_TIA"
        RunMacro("TIA VMT", opts) 
    end
    
    // Join vmt tables
    s1_vmt_df = CreateObject("df", S1_Dir + "\\output\\_summaries\\VMT_TIA\\TIA_VMT.csv")
    s2_vmt_df = CreateObject("df", S2_Dir + "\\output\\_summaries\\VMT_TIA\\TIA_VMT.csv")
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
    title = "Change in VMT Ratio"
    footnote = "Change in Zonal VMT"
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