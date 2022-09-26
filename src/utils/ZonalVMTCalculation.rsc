Macro "Open Zonal VMT Calculation Dbox" (Args)
	RunDbox("Zonal VMT Calculation", Args)
endmacro

dBox "Zonal VMT Calculation" (Args) center, center, 60, 10 
    Title: "Zonal VMT Calculation Tool" Help: "test" toolbox NoKeyBoard

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
    se_file = Args.[Input SE]
    reporting_dir = S1_Dir + "\\output\\_summaries"
    output_dir = reporting_dir + "\\Zonal_VMT_Comparison"
    //if GetDirectoryInfo(output_dir, "All") <> null then PutInRecycleBin(output_dir)
    RunMacro("Create Directory", output_dir)
    
    // Create output matrix
    out_file = output_dir + "\\ZonalVMT.mtx"
    S1_autotrip = reporting_dir + "\\resident_hb\\pa_veh_trips_AM.mtx"
    CopyFile(S1_autotrip, out_file)
    out_mtx = CreateObject("Matrix", out_file)
    out_core_names = out_mtx.GetCoreNames()
    out_mtx.AddCores({"temp"})
    out_mtx.DropCores(out_core_names)
    
    // Get scenario name and add related cores
    scen_Dirs = {S1_Dir, S2_Dir}
    comp_string = null
    for dir in scen_Dirs do
        parts = ParseString(dir, "\\")
        scen_name = parts[parts.length] 
        out_mtx.AddCores({"Autotrip_" + scen_name})
        out_mtx.AddCores({"Dist_" + scen_name})
        out_mtx.AddCores({"VMT_" + scen_name})
        comp_string = scen_name + "_" + comp_string
    end
    out_cores = out_mtx.GetCores() 

    // Loop through scenarios to get distance and auto trips
    i = 0
    for dir in scen_Dirs do
        i = i + 1
        // set input path
        skim_dir = dir + "\\output\\skims\\roadway"
        autotrip_dir = dir + "\\output\\_summaries\\resident_hb"
        skim_file = skim_dir + "\\skim_sov_MD.mtx" //use MD SOV file as distance
        
        // Get scenario name to create output name
        parts = ParseString(dir, "\\")
        scen_name = parts[parts.length] 
        
        // Calculate daily auto trip   
        for TOD in TOD_list do
            autotrip_file = autotrip_dir + "\\pa_veh_trips_" + TOD + ".mtx"
            auto_mtx = CreateObject("Matrix", autotrip_file)
            auto_cores = auto_mtx.GetCores()
            auto_corenames = auto_mtx.GetCoreNames()
            for name in auto_corenames do
                out_cores.("Autotrip_" + scen_name) := nz(out_cores.("Autotrip_" + scen_name)) + nz(auto_cores.(name))
            end
        end

        // Copy over distance
        skim_mtx = CreateObject("Matrix", skim_file)
        skim_cores = skim_mtx.GetCores()
        out_cores.("Dist_" + scen_name) := nz(skim_cores.("Length (Skim)"))

        // Calculate zonal VMT
        out_cores.("VMT_" + scen_name) := out_cores.("Dist_" + scen_name) * out_cores.("Autotrip_" + scen_name)
    end

    vmt_binfile = output_dir + "\\ZonalVMT.bin"
    out_mtx = OpenMatrix(out_file,)
    CreateTableFromMatrix(out_mtx, vmt_binfile, "FFB", {{"Complete", "No"}})
  
    // Aggregate by origin TAZ
    vmt_df = CreateObject("df", vmt_binfile)
    names = vmt_df.colnames()
    s1 = names[6]
    s2 = names[9]
    vmt_df.group_by("Origins")
    vmt_df.summarize({s1, s2}, "sum")
    names = vmt_df.colnames()
    for name in names do
        if Left(name, 4) = "sum_" then do
            new_name = Substitute(name, "sum_", "", 1)
            vmt_df.rename(name, new_name)
        end
    end

    // Calculate VMT per capita and VMTratio
    se_df = CreateObject("df", se_file)
    se_df.select({"TAZ", "HH_POP"})
    vmt_df.left_join(se_df, "Origins", "TAZ")
    vmt_df.mutate(s1 + "_percap", nz(vmt_df.tbl.(s1)/vmt_df.tbl.HH_Pop)) //calculate S1 zonal vmt per capita
    vmt_df.mutate(s2 + "_percap", nz(vmt_df.tbl.(s2)/vmt_df.tbl.HH_Pop)) //calculate S2 zonal vmt per capita
    s1_percap = vmt_df.get_col(s1 + "_percap")
    s2_percap = vmt_df.get_col(s2 + "_percap")
    s1_avgpercap = Avg(V2A(s1_percap)) //calculate S1 average zonal vmt per capita
    s2_avgpercap = Avg(V2A(s2_percap))

    vmt_df.mutate(s1 + "_ratio", vmt_df.tbl.(s1 + "_percap")/s1_avgpercap) //calculate per capita
    vmt_df.mutate(s2 + "_ratio", vmt_df.tbl.(s2 + "_percap")/s2_avgpercap)
    vmt_df.mutate("Ratio_Delta", nz(vmt_df.tbl.(s1 + "_ratio")) - nz(vmt_df.tbl.(s2 + "_ratio")))
    vmt_df.write_bin(output_dir + "/Comparison_zonalVMT.bin")

    // Mapping VMT delta on a taz map
    vw = OpenTable("vw", "FFB", {output_dir + "/Comparison_zonalVMT.bin"})
    mapFile = output_dir + "/" + comp_string + "Comparison_ZonalVMT.map"
    {map, {tlyr}} = RunMacro("Create Map", {file: taz_file})
    jnvw = JoinViews("jv", tlyr + ".ID", vw + ".Origins",)
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

    cTheme = CreateTheme("ZonalVMT", jnvw+".Ratio_Delta", "Equal Steps" , numClasses, opts)

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
    title = "Zonal VMT Changes"
    //footnote = "Transit travel time capped, see user guide."
    SetLegendSettings (
      GetMap(),
      {
        "Automatic",
        {0, 1, 0, 0, 1, 4, 0},
        {1, 1, 1},
        {"Arial|Bold|14", "Arial|9", "Arial|Bold|12", "Arial|12"},
        {title, }
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