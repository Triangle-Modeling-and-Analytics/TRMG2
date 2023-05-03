Macro "Open Transit Scenario Comparison Dbox" (Args)
	RunDbox("Transit Scenario Comparison", Args)
endmacro

dBox "Transit Scenario Comparison" (Args) location: center, center, 60, 11
  Title: "Transit Scenario Comparison" toolbox NoKeyBoard

  // What happens when the "x" is clicked
  close do
    return()
  enditem

  init do

    static TOD, S2_Dir, TOD_Index, TOD_list, S1_Dir, S1_Name, Scen_Dir
    
    Scen_Dir = Args.[Scenarios Folder]
    S1_Dir = Args.[Scenario Folder]
    S1_Name = Substitute(S1_Dir, Scen_Dir + "\\", "",)
    TOD_list = Args.Periods

	EnableItem("Select TOD")
	  
   enditem
  


  // Comparing Scenario directory text and button
  text 5, 1 variable: "Old/Base Scenario Directory:"
  text same, after, 40 variable: S2_Dir framed
  button after, same, 6 Prompt: "..." do

    on escape goto nodir
    S2_Dir = ChooseDirectory("Choose the old/base scenario directory:", )

    nodir:
    on error, notfound, escape default
  enditem 

  // TOD Button
  Popdown Menu "Select TOD" 16,6,10,5 Prompt: "Choose TOD" 
    List: TOD_list Variable: TOD_Index do
    TOD = TOD_list[TOD_Index]
  enditem

  // New Scenario
  Text 38, 4, 15 Prompt: "New Scenario (selected in scenario list):" Variable: S1_Name

  // Quit Button
  button 7, 9, 10 Prompt:"Quit" do
    Return(1)
  enditem

  // Run Button
  button 21, 9, 30 Prompt:"Generate Results" do 

    if !RunMacro("TransitScenarioComparison", Args, S2_Dir, TOD) then Throw("Something went wrong")
 
    ShowMessage("Reports have been created successfully.")
	return(1)
	
    exit:	
    showmessage("Something is wrong")	
    return(0)
  Enditem
Enddbox

//@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
//                        Macro "TransitScenarioComparison"
//@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
Macro "TransitScenarioComparison" (Args, S2_Dir, TOD) 
    // Set working directory
    S1_Dir = Args.[Scenario Folder]
    reporting_dir = S1_Dir + "\\output\\_summaries"
    output_dir = reporting_dir + "\\Transit_Scenario_Comparison"
    tod_dir = output_dir + "\\" + TOD
    TransModeTable = Args.TransModeTable
    if GetDirectoryInfo(output_dir, "All") <> null then PutInRecycleBin(output_dir)
    RunMacro("Create Directory", reporting_dir) //need to create this during create scenario step
    RunMacro("Create Directory", output_dir)
    RunMacro("Create Directory", tod_dir)

    //Loop through all mtx under skim folder
    comp_string = null
    scen_Dirs = {S1_Dir, S2_Dir}
    i = 0
    for dir in scen_Dirs do
        i = i + 1
        skim_dir_transit = dir + "\\output\\skims\\transit"
        parts = ParseString(dir, "\\")
        scen_name = parts[parts.length]
        
        // Create a matrix to store results (only do this once)
        trn_skim_file = skim_dir_transit + "/skim_" + TOD + "_w_all.mtx"
        if i = 1 then do
            out_file = tod_dir + "/Comparisons_" + "_" + TOD + ".mtx"
            CopyFile(trn_skim_file, out_file)
            mtx = CreateObject("Matrix", out_file)
            core_names = mtx.GetCoreNames()
            mtx.AddCores({"temp"})
            mtx.DropCores(core_names)
        end

        //loop through all transit modes under walk access
        mtx.AddCores({scen_name + "_trips"})
        mtx.AddCores({scen_name + "_skims"})        
        mtx.AddCores({scen_name + "_wttime"})        

        transit_modes = RunMacro("Get Transit Modes", TransModeTable)
        transit_modes = {"all"} + transit_modes
        for transit_mode in transit_modes do

          //Fill output trip core 
          trip_Dir = dir + "\\output\\assignment\\transit"
          trip_file = trip_Dir + "/transit_" + TOD + ".mtx"
          trip_mtx = CreateObject("Matrix", trip_file)
          mtx.(scen_name + "_trips") := nz(mtx.(scen_name + "_trips")) + nz(trip_mtx.("w_" + transit_mode))

          //Fill output skim core
          trn_skim_file = skim_dir_transit + "/skim_" + TOD + "_w_" + transit_mode + ".mtx"
          skim_mtx = CreateObject("Matrix", trn_skim_file)
          mtx.(scen_name + "_skims") := if nz(mtx.(scen_name + "_skims")) = 1 then 1 else if nz(skim_mtx.("Total Time"))> 0 and nz(skim_core)<60 then 1 else 0

          //Fill output wttime core
          mtx.(scen_name + "_wttime") := nz(mtx.(scen_name + "_wttime")) + nz(mtx.(scen_name + "_trips")) * nz(skim_mtx.("Total Time"))

        end

        //build a comp name
        comp_string = scen_name + "_" + comp_string
    end
    
    comp_binfile = tod_dir + "/" + comp_string + "_" + TOD + "_comparison.bin"
    matrix = OpenMatrix(out_file,)
    CreateTableFromMatrix(matrix, comp_binfile, "FFB", {{"Complete", "No"}})
  
    //Open comp bin and Aggregate by origin TAZ
    df = CreateObject("df", comp_binfile)
    names = df.colnames()
    fields_to_sum =  ExcludeArrayElements(names, 1, 3)
    df.group_by("RCIndex")
    df.summarize(fields_to_sum, "sum")
    
    names = df.colnames()
    for name in names do
      if Left(name, 4) = "sum_" then do
            new_name = Substitute(name, "sum_", "", 1)
            df.rename(name, new_name)
        end
    end
    names = df.colnames()
    df.mutate("Delta_wttime", df.tbl.(names[7])/df.tbl.(names[5]) - df.tbl.(names[4])/df.tbl.(names[2])) // wttime = E(trips*time)/trips
    df.mutate("Delta_access", df.tbl.(names[6]) - df.tbl.(names[3]))
    df.mutate("Delta_trips", df.tbl.(names[5]) - df.tbl.(names[2]))
    df.rename("RCIndex", "TAZ")
    df.write_csv(tod_dir + "/" + comp_string + "_" + TOD + "_comparison.csv")
 
    //Mapping TT
    taz_file = Args.TAZs
    mapFile = tod_dir + "/" + comp_string + "Comparison_TravelTime_" + TOD + ".map"
    {map, {tlyr}} = RunMacro("Create Map", {file: taz_file})
    vw = OpenTable("vw", "CSV", {tod_dir + "/" + comp_string + "_" + TOD + "_comparison.csv", })
    jnvw = JoinViews("jv", tlyr + ".ID", vw + ".TAZ",)
    SetView(jnvw)

    // Create a theme for the travel time difference
    numClasses = 4
    opts = null
    opts.[Pretty Values] = "True"
    opts.[Drop Empty Classes] = "True"
    opts.Title = "On average by origin zone in " + TOD
    opts.Other = "False"
    opts.[Force Value] = 0
    opts.zero = "TRUE"

    cTheme = CreateTheme("Transit Time", jnvw+".Delta_wttime", "Equal Steps" , numClasses, opts)

    // Set theme fill color and style
    opts = null
    a_color = {
      ColorRGB(8738, 24158, 43176),
      ColorRGB(16705, 46774, 50372),
      ColorRGB(41377, 56026, 46260),
      ColorRGB(65535, 65535, 54248)
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
    title = "Transit Travel Time Changes"
    footnote = "Transit travel time capped, see user guide."
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
    ///////////////////////////////////////////////////////////////////////////////////////
    //Mapping Trips
    taz_file = Args.TAZs
    mapFile = tod_dir + "/" + comp_string + "Comparison_Trips_" + TOD + ".map"
    {map, {tlyr}} = RunMacro("Create Map", {file: taz_file})
    jnvw = JoinViews("jv", tlyr + ".ID", vw + ".TAZ",)
    SetView(jnvw)

    // Create a theme for the travel time difference
    numClasses = 4
    opts = null
    opts.[Pretty Values] = "True"
    opts.[Drop Empty Classes] = "True"
    opts.Title = "in total by origin zone in " + TOD
    opts.Other = "False"
    opts.[Force Value] = 0
    opts.zero = "TRUE"

    cTheme = CreateTheme("Transit Time", jnvw+".Delta_trips", "Equal Steps" , numClasses, opts)

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
    title = "Transit Trips Changes"
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
    
    //Compare route level difference
    //Set up file path
    s1_routefolder = S1_Dir + "/output/_summaries/transit"
    s2_routefolder = S2_Dir + "/output/_summaries/transit"
    s1_boardingfile = s1_routefolder + "/boardings_and_alightings_by_period.csv"
    s2_boardingfile = s2_routefolder + "/boardings_and_alightings_by_period.csv"
    s1_pmilefile = s1_routefolder + "/passenger_miles_and_hours.csv"
    s2_pmilefile = s2_routefolder + "/passenger_miles_and_hours.csv"
    scen_rts = Args.[Input Routes]
    
    //Get agency name
    rts_bin = Substitute(scen_rts, ".rts", "R.bin", 1)
    df3 = CreateObject("df", rts_bin)
    df3.select({"Route_ID", "Agency", "Route_Name"})

    //Get scen name
    parts = ParseString(S1_Dir, "\\")
    s1_name = parts[parts.length]
    parts = ParseString(S2_Dir, "\\")
    s2_name = parts[parts.length]
    
    //boardings by route/agency and TOD
    df1 = null 
    df1 = CreateObject("df", s1_boardingfile)
    df1.filter("period = '" + TOD + "'")
    df1.group_by("route")
    df1.summarize({"On", "Off"}, "sum")
    //df1.mutate("JoinID", string(df1.tbl.("route")) + df1.tbl.("access") + df1.tbl.("mode"))    

    df2 = null 
    df2 = CreateObject("df", s2_boardingfile)
    df2. filter("period = '" + TOD + "'")
    df2.group_by("route")
    df2.summarize({"On", "Off"}, "sum")
    //df2.mutate("JoinID", string(df2.tbl.("route")) + df2.tbl.("access") + df2.tbl.("mode"))

    df1.left_join(df2, "route", "route")
    df1.mutate("Delta_On", nz(df1.tbl.("sum_On_x")) - nz(df1.tbl.("sum_On_y"))) 
    df1.mutate("Delta_Off", nz(df1.tbl.("sum_Off_x")) - nz(df1.tbl.("sum_Off_y")))
    df1.select({"route", "sum_On_x", "sum_Off_x", "sum_On_y", "sum_Off_y", "Delta_On", "Delta_Off"})

    //by route
    df1.group_by("route")
    df1.summarize({"sum_On_x", "sum_Off_x", "sum_On_y", "sum_Off_y", "Delta_On", "Delta_Off"}, "sum")
    df1.left_join(df3, "route", "Route_ID")
    names = df1.colnames()
    for name in names do
        if Left(name, 4) = "sum_" then do
            new_name = Substitute(name, "sum_", "", 1)
            new_name = Substitute(new_name, "sum_", "", 1) //some fields start with sum_sum_
            new_name = Substitute(new_name, "x", s1_name, 1)
            new_name = Substitute(new_name, "y", s2_name, 1)
            df1.rename(name, new_name)
        end
    end
    
    df1.write_csv(tod_dir + "/boardings_alightings_byroute_" + TOD + ".csv")

    //by agency
    df1.group_by("Agency")
    df1.summarize({"On_"+s1_name, "Off_"+s1_name, "On_"+s2_name, "Off_"+s2_name, "Delta_On", "Delta_Off"}, "sum")
    names = df1.colnames()
    for name in names do
        if Left(name, 4) = "sum_" then do
            new_name = Substitute(name, "sum_", "", 1)
            df1.rename(name, new_name)
        end
    end
    df1.write_csv(tod_dir + "/boardings_alightings_byagency_" + TOD + ".csv")

    //passenger miles and hours by route and agency
    df1 = null 
    df1 = CreateObject("df", s1_pmilefile)
    df1.group_by("route")
    df1.summarize({"pass_hours", "pass_miles"}, "sum")

    df2 = null 
    df2 = CreateObject("df", s2_pmilefile)
    df2.group_by("route")
    df2.summarize({"pass_hours", "pass_miles"}, "sum")

    df1.left_join(df2, "route", "route")
    df1.mutate("Delta_hours", nz(df1.tbl.("sum_pass_hours_x")) - nz(df1.tbl.("sum_pass_hours_y")))
    df1.mutate("Delta_miles", nz(df1.tbl.("sum_pass_miles_x")) - nz(df1.tbl.("sum_pass_miles_y")))
    names = df1.colnames()
    for name in names do
        if Left(name, 4) = "sum_" then do
            new_name = Substitute(name, "sum_", "", 1)
            new_name = Substitute(new_name, "x", s1_name, 1)
            new_name = Substitute(new_name, "y", s2_name, 1)
            df1.rename(name, new_name)
        end
    end

    //by route
    df1.left_join(df3, "route", "Route_ID")
    df1.write_csv(output_dir + "/passhoursandmiles_byroute_daily.csv")

    //by agency
    df1.group_by("Agency")
    df1.summarize({"pass_hours_"+s1_name, "pass_miles_"+s1_name, "pass_hours_"+s2_name, "pass_miles_"+s2_name, "Delta_hours", "Delta_miles"}, "sum")
    names = df1.colnames()
    for name in names do
        if Left(name, 4) = "sum_" then do
            new_name = Substitute(name, "sum_", "", 1)
            df1.rename(name, new_name)
        end
    end
    df1.write_csv(output_dir + "/passhoursandmiles_byagency_daily.csv")
    
    RunMacro("Close All")
    mtx = null
    matrix = null
    out_skim_core = null
    out_trip_core = null
    //DeleteFile(out_file)
    DeleteFile(Substitute(comp_binfile, ".bin", ".DCB",))
    DeleteFile(comp_binfile)
    Return(1)
endmacro