Macro "Open Transit Scenario Comparison Dbox" (Args)
	RunDbox("Transit Scenario Comparison", Args)
endmacro

dBox "Transit Scenario Comparison" (Args) location: center, center, 80, 20
  Title: "Transit Scenario Comparison" toolbox NoKeyBoard

  // What happens when the "x" is clicked
  close do
    return()
  enditem

  init do

    static TOD, S2_Dir, TOD_Index, TOD_list
	
    TOD_list = Args.Periods

	EnableItem("Select TOD")
	  
   enditem
  
  // Quit Button
  button 5, 15, 10 Prompt:"Quit" do
    Return(1)
  enditem

  // TOD Button
  Popdown Menu "Select TOD" 16,10,10,5 Prompt: "Choose TOD" 
    List: TOD_list Variable: TOD_Index do
    TOD = TOD_list[TOD_Index]
  enditem

  // Comparing Scenario directory text and button
  text 5, 0 variable: "Comparing Scenario Directory:"
  text same, after, 40 variable: S2_Dir framed
  button after, same, 6 Prompt: "..." do

    on escape goto nodir
    S2_Dir = ChooseDirectory("Choose the scenario directory which you like to compare with:", )

    nodir:
    on error, notfound, escape default
  enditem 

  // Make Map Button
  button 19, 15, 30 Prompt:"Generate Results" do 

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
    reporting_dir = S1_Dir + "\\output\\_summaries\\_reportingtool"
    output_dir = reporting_dir + "\\Transit Scenario Comparison"
    if GetDirectoryInfo(output_dir, "All") <> null then PutInRecycleBin(output_dir)
    RunMacro("Create Directory", reporting_dir) //need to create this during create scenario step
    RunMacro("Create Directory", output_dir)
    
    //Loop through all mtx under skim folder
    scen_Dirs = {S1_Dir, S2_Dir}
    i = 0
    for dir in scen_Dirs do
        i = i + 1
        skim_dir_transit = dir + "\\output\\skims\\transit"
        //skim_dir_walk = dir + "\\output\\skims\\nonmotorized"
        parts = ParseString(dir, "\\")
        scen_name = parts[parts.length]
        //trn_skim_files = RunMacro("Catalog Files", {dir: skim_dir_transit, ext: "mtx"})
        
        trn_skim_file = skim_dir_transit + "/skim_" + TOD + "_w_all.mtx"
        // Create a starting transit matrix to store results (only do this once)
        if i = 1 then do
            out_file = output_dir + "/TransitShortestPath_" + scen_name + "_" + TOD + ".mtx"
            CopyFile(trn_skim_file, out_file)
            mtx = CreateObject("Matrix", out_file)
            core_names = mtx.GetCoreNames()
            mtx.AddCores({"Temp"})
            mtx.DropCores(core_names)
        end

        /*
        // Create a starting transit matrix to store results (only do this once)
        if i = 1 then do
            out_file = output_dir + "/TransitShortestPath_" + scen_name + "_" + TOD + ".mtx"
            CopyFile(trn_skim_files[1], out_file)
            mtx = CreateObject("Matrix", out_file)
            core_names = mtx.GetCoreNames()
            mtx.AddCores({"Temp"})
            mtx.DropCores(core_names)
        end
        */

        // Create cores for each scenario to store SP and total trips
        mtx.AddCores({scen_name + "_w_skim"})
        mtx.AddCores({scen_name + "_trips"})
        out_skim_core = mtx.GetCore(scen_name + "_w_skim")
        out_trip_core = mtx.GetCore(scen_name + "_trips")
        out_skim_core := 0
        out_trip_core := 0
        
        skim_mtx = CreateObject("Matrix", trn_skim_file)
        skim_core = skim_mtx.GetCore("Total Time")
        //out_skim_core := if nz(skim_core)<=60 then nz(skim_core) else 0
        out_skim_core := nz(skim_core)

        /*
        //Loop through all transit mtx in that TOD to get shortest path
        j = 0
        for trn_skim_file in trn_skim_files do
            {, , name, } = SplitPath(trn_skim_file)
            if !Position(name, TOD) then continue //if mtx is not for this TOD, skip
            j = j + 1
            skim_mtx = CreateObject("Matrix", trn_skim_file)
            skim_core = skim_mtx.GetCore("Total Time")
            if j =1 then out_skim_core := nz(skim_core)
            else out_skim_core := if out_skim_core = 0  then nz(skim_core) 
                                    else if nz(skim_core) < out_skim_core and nz(skim_core)>0 then nz(skim_core) else out_skim_core
        end

        //Transit skim time may not be available to all OD pairs - in this case, use walk time
        wlk_skim_file = skim_dir_walk + "/walk_skim.mtx"
        skim_mtx = CreateObject("Matrix", wlk_skim_file)
        skim_core = skim_mtx.GetCore("WalkTime")
        out_skim_core := if out_skim_core = 0  then nz(skim_core) else out_skim_core
        */

        //Open transit trip mtx and sum up cores to SP mtx to get total trips OD
        trip_Dir = dir + "\\output\\\assignment\\transit"
        trip_file = trip_Dir + "/transit_" + TOD + ".mtx"
        trip_mtx = CreateObject("Matrix", trip_file)
        trip_core_names = trip_mtx.GetCoreNames()
        for trip_core_name in trip_core_names do
            trip_core = trip_mtx.GetCore(trip_core_name)
            out_trip_core := out_trip_core + nz(trip_core)
        end
    end
    
    sp_binfile = output_dir + "/Transit_" + TOD + "_SP.bin"
    matrix = OpenMatrix(out_file,)
    CreateTableFromMatrix(matrix, sp_binfile, "FFB", {{"Complete", "No"}})
  
    //Open sp bin and filter records to exclude OD pairs without access
    //Aggregate by origin TAZ
    sp_vw = OpenTable("sp", "FFB", {sp_binfile})
    SetView(sp_vw)
    {fields, } = GetFields(sp_vw,)
    s1_tt = fields[4]
    s1_trip = fields[5]
    s2_tt = fields[6]
    s2_trip = fields[7]
    del_set = CreateSet("to_delete")
    n = SelectByQuery(del_set, "Several", "Select * where " + s1_tt + "=0 and " +  s2_tt + "=0")
    if n > 0 then DeleteRecordsInSet(del_set)
    
    //Calculate delta
    a_fields =  {
        {"Delta_Time", "Real", 10, 1,,,, "Change in user transit travel time"},
        {"Delta_Trips", "Real", 10, ,,,, "Change in user transit trips"},
        {"Delta_Access", "Real", 10, ,,,, "Change in number of TAZ destinations a user can reach by transit"}
    }
    RunMacro("Add Fields", {view: sp_vw, a_fields: a_fields})
    {v_s1_tt, v_s1_trip, v_s2_tt, v_s2_trip} = GetDataVectors(
        sp_vw + "|",
        {
            s1_tt,
            s1_trip,
            s2_tt,
            s2_trip
        },
    )

    //eliminate transit time over 60 minutes (unrealistic)
    v_s1_tt = if v_s1_tt < 60 then v_s1_tt else if v_s2_tt < 60 and v_s2_tt >0 then v_s1_tt else 0
    v_s2_tt = if v_s2_tt < 60 then v_s2_tt else if v_s1_tt < 60 and v_s1_tt >0 then v_s2_tt else 0
    SetDataVector(sp_vw + "|", s1_tt, v_s1_tt, )
    SetDataVector(sp_vw + "|", s2_tt, v_s2_tt, )
    
    //Calculate delta
    v_Time = if v_s1_tt > 0 and v_s2_tt > 0 then v_s1_tt - v_s2_tt else 0
    v_Trips = v_s1_trip - v_s2_trip
    v_Access = if v_s1_tt = 0 and v_s2_tt > 0 then -1 else if v_s1_tt > 0 and v_s2_tt = 0 then 1 else 0
    SetDataVector(sp_vw + "|", "Delta_Time", v_Time, )
    SetDataVector(sp_vw + "|", "Delta_Trips", v_Trips, )
    SetDataVector(sp_vw + "|", "Delta_Access", v_Access, )
    
    //Aggregate by origin TAZ
    grouped_vw1 = AggregateTable(
        "grouped_vw1", sp_vw + "|", "FFB", output_dir + "/Comparison_" + TOD + ".bin", "RCIndex", 
        {{"Delta_Time", "SUM", }, {"Delta_Trips", "SUM",}, {"Delta_Access", "SUM",}}, 
        {"Missing As Zero": "true"}
    )

    //Remove -0.0
    vw = OpenTable("vw", "FFB", {output_dir + "/Comparison_" + TOD + ".bin"})
    {v1, v2} = GetDataVectors(vw+"|", {"Delta_Time", "Delta_Trips"}, )
    v1 = Round(v1, 1)
    v2 = Round(v2,0)
    SetDataVector(vw + "|", "Delta_Time", v1, )
    SetDataVector(vw + "|", "Delta_Trips", v2, )
 
    
    //Mapping
    taz_file = Args.TAZs
    mapFile = output_dir + "/Comparison_TravelTime_" + TOD + ".map"
    {map, {tlyr}} = RunMacro("Create Map", {file: taz_file})
    jnvw = JoinViews("jv", tlyr + ".ID", vw + ".RCIndex",)
    SetView(jnvw)

    // Create a theme for the travel time difference
    numClasses = 4
    opts = null
    opts.[Pretty Values] = "True"
    opts.Title = "Change in Transit Travel Time (Minutes)"
    opts.Other = "False"
    opts.[Force Value] = 0
    opts.zero = "TRUE"

    cTheme = CreateTheme("Transit Time", jnvw+".Delta_Time", "Equal Steps" , numClasses, opts)

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
    info = GetThemeClasses(cTheme)
    SetThemeClassLabels(cTheme, cls_labels)

    // Configure Legend
    SetLegendDisplayStatus(cTheme, "True")
    RunMacro("G30 create legend", "Theme")
    subtitle = TOD + " Period"
    SetLegendSettings (
      GetMap(),
      {
        "Automatic",
        {0, 1, 0, 0, 1, 4, 0},
        {1, 1, 1},
        {"Arial|Bold|16", "Arial|9", "Arial|Bold|16", "Arial|12"},
        {"", subtitle}
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
    df3.select({"Route_ID", "Agency"})

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
    df1.mutate("Delta_On", df1.tbl.("sum_On_x") - df1.tbl.("sum_On_y")) 
    df1.mutate("Delta_Off", df1.tbl.("sum_Off_x") - df1.tbl.("sum_Off_y"))
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
    
    df1.write_csv(output_dir + "/boardings_alightings_byroute_" + TOD + ".csv")

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
    df1.write_csv(output_dir + "/boardings_alightings_byagency_" + TOD + ".csv")

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
    df1.mutate("Delta_hours", df1.tbl.("sum_pass_hours_x") - df1.tbl.("sum_pass_hours_y")) 
    df1.mutate("Delta_miles", df1.tbl.("sum_pass_miles_x") - df1.tbl.("sum_pass_miles_y"))
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
    Return(1)
endmacro