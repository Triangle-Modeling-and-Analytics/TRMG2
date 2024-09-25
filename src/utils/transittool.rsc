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
  text 5, 1 variable: "Old/Base Scenario Directory: (optional)"
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

  Button 40, 9, 10 Prompt: "Help" do
        ShowMessage(
            "This tool allows you to select two previously-run scenarios to " +
            "compare their transit performance. The base/old scenario is optional." +
            "If you leave it blank, the tool will only generate results for the " +
            "new scenario instead of doing comparison."
        )
    enditem
  
  // Run Button
  button 23, 9, 10 Prompt:"Run" do 

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
    taz_file = Args.TAZs

    //Loop through each scenario
    comp_string = null
    if S2_Dir <> null then scen_Dirs = {S1_Dir, S2_Dir}
    else scen_Dirs = {S1_Dir}

    for dir in scen_Dirs do
        // Set output path and scenario name
        output_dir = dir + "\\output\\_summaries\\Transit_Scenario_Comparison"
        tod_dir  = output_dir + "\\" + TOD
        se_file = dir + "\\output\\sedata\\scenario_se.bin"
        RunMacro("Create Directory", output_dir)
        RunMacro("Create Directory", tod_dir)
        data = null

        skim_dir_transit = dir + "\\output\\skims\\transit"
        parts = ParseString(dir, "\\")
        scen_name = parts[parts.length]
        
        // 0. Create the output table 
        out_binfile = tod_dir + "\\TransitEval_" + TOD + ".bin"
        out_vw = CreateTable("out", out_binfile, "FFB", {
            {"TAZ", "Integer", 10, , , "Zone ID"}
        })
        se_vw = OpenTable("se", "FFB", {se_file})
        taz = GetDataVector(se_vw + "|", "TAZ", )
        n = GetRecordCount(se_vw, )
        AddRecords(out_vw, , , {"empty records": n})
        SetDataVector(out_vw + "|", "TAZ", taz, )
        CloseView(se_vw)
        CloseView(out_vw)
        
        // 1. Create a matrix to store results
        trn_skim_file = skim_dir_transit + "/skim_" + TOD + "_w_all.mtx"
        out_mtxfile = tod_dir + "/TransitEval_" + TOD + ".mtx"
        CopyFile(trn_skim_file, out_mtxfile)
        mtx = CreateObject("Matrix", out_mtxfile)
        core_names = mtx.GetCoreNames()

        mtx.AddCores({scen_name + "_trips", scen_name + "_access", scen_name + "_wttime"})     
        mtx.DropCores(core_names)

        //2. loop through all transit modes under walk access
        TransModeTable = dir + "\\input\\networks\\transit_mode_table.csv"
        transit_modes = RunMacro("Get Transit Modes", TransModeTable)
        transit_modes = {"all"} + transit_modes
        for transit_mode in transit_modes do
            //Fill output trip core 
            trip_Dir = dir + "\\output\\assignment\\transit"
            trip_file = trip_Dir + "/transit_" + TOD + ".mtx"
            trip_mtx = CreateObject("Matrix", trip_file)
            mtx.(scen_name + "_trips") := nz(mtx.(scen_name + "_trips")) + nz(trip_mtx.("w_" + transit_mode))

            //Fill output access core
            trn_skim_file = skim_dir_transit + "/skim_" + TOD + "_w_" + transit_mode + ".mtx"
            skim_mtx = CreateObject("Matrix", trn_skim_file)
            mtx.(scen_name + "_access") := if nz(mtx.(scen_name + "_access")) = 1 then 1 else if nz(skim_mtx.("Total Time"))> 0 and nz(skim_mtx.("Total Time"))<60 then 1 else 0 //if time <60. then count as accessible

            //Fill output wttime core
            mtx.(scen_name + "_wttime") := nz(mtx.(scen_name + "_wttime")) + nz(mtx.(scen_name + "_trips")) * nz(skim_mtx.("Total Time"))
        end
        trip_mtx = null
        skim_mtx = null
        
        //3. Calculate row sum for trips, access, and wttime
        v_trips = mtx.GetVector({Core: scen_name + "_trips", Marginal: "Row Sum"})
        v_access = mtx.GetVector({Core: scen_name + "_access", Marginal: "Row Sum"})
        v_wttime = mtx.GetVector({Core: scen_name + "_wttime", Marginal: "Row Sum"})
        data.(scen_name + "_trips") = nz(v_trips)
        data.(scen_name + "_access") = nz(v_access)
        data.(scen_name + "_wttime") = nz(v_wttime)
        
        //4. Fill population and employment
        a_fields = {"Job", "Pop"}
        se = CreateObject("Table", se_file)
	      v_job = se.TotalEmp
        v_pop = se.HH_POP
	      mtx.AddCores(a_fields)
	      mtx.Job := v_job
        mtx.Pop := v_pop

        for field in a_fields do

          out_core = scen_name + "_access_" + field
          mtx.AddCores({out_core})
          mtx.(out_core) := if mtx.(scen_name + "_access") = 1 then mtx.(field)
          v = mtx.GetVector({Core: out_core, Marginal: "Row Sum"})
          v.rowbased = "true"

          data.(out_core) = nz(v)
        end

        //5. Fill in the raw output table
        out_vw = OpenTable("out", "FFB", {out_binfile})
        fields_to_add = { {scen_name + "_trips", "Real", 10, 2,,,, "Transit trips originated from this zone"},
                          {scen_name + "_access", "Real", 10, 2,,,, "Number of zones accessible by this zone via walk to transit under 60 min"},
                          {scen_name + "_wttime", "Real", 10, 2,,,, "Total transit travel time originated from this zone, weighted by number of transit trips"},
                          {scen_name + "_access_job", "Real", 10, 2,,,, "Jobs accessible within 60 min"},
                          {scen_name + "_access_pop", "Real", 10, 2,,,, "Population accessible within 60 min"}}
        RunMacro("Add Fields", {view: out_vw, a_fields: fields_to_add})
        SetDataVectors(out_vw + "|", data, )
        CloseView(out_vw)
        mtx = null
        DeleteFile(out_mtxfile)

        //build a comp name
        comp_string = scen_name + "_" + comp_string
    end

    /////////////////////////////////////////////////////////////////////////////////////////////
    // 4. Start comparison if S2<>NULL
    if S2_Dir <> null then do 
      // 4.1 Calculate Delta
      S1_output_dir = S1_Dir + "\\output\\_summaries\\Transit_Scenario_Comparison"
      S1_tod_dir = S1_Dir + "\\output\\_summaries\\Transit_Scenario_Comparison\\" + TOD
      df_S1 = CreateObject("Table", S1_tod_dir + "\\TransitEval_" + TOD + ".bin")
      S2_tod_dir = S2_Dir + "\\output\\_summaries\\Transit_Scenario_Comparison\\" + TOD
      df_S2 = CreateObject("Table", S2_tod_dir + "\\TransitEval_" + TOD + ".bin")

      fields = {
        {FieldName: "Diff_avgwttime", Type: "real"},
        {FieldName: "Diff_access", Type: "real"},
        {FieldName: "Diff_trips", Type: "real"},
        {FieldName: "Diff_access_job", Type: "real"},
        {FieldName: "Diff_access_pop", Type: "real"},
        {FieldName: "PctDiff_avgwttime", Type: "real"},
        {FieldName: "PctDiff_access", Type: "real"},
        {FieldName: "PctDiff_trips", Type: "real"},
        {FieldName: "PctDiff_access_job", Type: "real"},
        {FieldName: "PctDiff_access_pop", Type: "real"}
      }
      df_S2.AddFields({Fields: fields})
      df_S2.RenameField({FieldName:"TAZ", NewName: "TAZ_todelete"})
      
      join = df_S1.Join({
      Table: df_S2,
      LeftFields: "TAZ",
      RightFields: "TAZ_todelete"
      })

      names = join.GetFieldNames()
      join.Diff_avgwttime = join.(names[4])/join.(names[2]) - join.(names[10])/join.(names[8]) // wttime = E(trips*time)/trips
      join.Diff_access = join.(names[3]) - join.(names[9])
      join.Diff_trips = join.(names[2]) - join.(names[8])
      join.Diff_access_job = join.(names[5]) - join.(names[11])
      join.Diff_access_pop = join.(names[6]) - join.(names[12])

      join.PctDiff_avgwttime = if join.(names[10])/join.(names[8]) >0 then join.Diff_avgwttime/join.(names[10])/join.(names[8]) else null
      join.PctDiff_access = if join.(names[9]) >0 then join.Diff_access / join.(names[9]) else null
      join.PctDiff_trips = if join.(names[8]) > 0 then join.Diff_trips / join.(names[8]) else null
      join.PctDiff_access_job = if join.(names[11]) > 0 then join.Diff_access_job / join.(names[11]) else null
      join.PctDiff_access_pop = if join.(names[12])  >0 then join.Diff_access_pop / join.(names[12]) else null

      join.Export({FileName: S1_tod_dir + "\\temp.csv"})
      df_S1 = null
      df_S2 = null
      join = null
      df = CreateObject("Table", S1_tod_dir + "\\temp.csv")
      df.DropFields("TAZ_todelete")
      df.Export({FileName: S1_tod_dir + "\\" + comp_string + "_" + TOD + "_comparison.csv"})
      df = null
      DeleteFile(S1_tod_dir + "\\temp.csv")
      DeleteFile(S1_tod_dir + "\\temp.dcc")

      //4.2 Compare route level difference
      //    Set up file path
      s1_routefolder = S1_Dir + "/output/_summaries/transit"
      s2_routefolder = S2_Dir + "/output/_summaries/transit"
      s1_boardingfile = s1_routefolder + "/boardings_and_alightings_by_period.csv"
      s2_boardingfile = s2_routefolder + "/boardings_and_alightings_by_period.csv"
      s1_pmilefile = s1_routefolder + "/passenger_miles_and_hours.csv"
      s2_pmilefile = s2_routefolder + "/passenger_miles_and_hours.csv"
      s1_scen_rts = S1_Dir + "\\input\\networks\\scenario_routesR.bin" //The join will base in S1 scenario, so if S2 has route that does not exist in S1, it will lost.
      s2_scen_rts = S2_Dir + "\\input\\networks\\scenario_routesR.bin" //The join will base in S1 scenario, so if S2 has route that does not exist in S1, it will lost.
    
      //    Get agency name
      df_s1_rts = CreateObject("df", s1_scen_rts)
      df_s1_rts.select({"Route_ID", "Agency", "Route_Name"})
      df_s2_rts = CreateObject("df", s2_scen_rts)
      df_s2_rts.select({"Route_ID", "Agency", "Route_Name"})

      //    Get scen name
      parts = ParseString(S1_Dir, "\\")
      s1_name = parts[parts.length]
      parts = ParseString(S2_Dir, "\\")
      s2_name = parts[parts.length]
    
      //4.2.1 boardings by route/agency and TOD
      df_S1 = CreateObject("df", s1_boardingfile)
      df_S1.filter("period = '" + TOD + "'")
      df_S1.group_by("route")
      df_S1.summarize({"On", "Off"}, "sum")
      df_S1.left_join(df_s1_rts, "route", "Route_ID")

      df_S2 = null 
      df_S2 = CreateObject("df", s2_boardingfile)
      df_S2. filter("period = '" + TOD + "'")
      df_S2.group_by("route")
      df_S2.summarize({"On", "Off"}, "sum")
      df_S2.left_join(df_s2_rts, "route", "Route_ID")
   
      join = df_S1.outer_join(df_S2, "Route_Name", "Route_Name")
      join.mutate("Delta_On", nz(join.tbl.("sum_On_x")) - nz(join.tbl.("sum_On_y"))) 
      join.mutate("Delta_Off", nz(join.tbl.("sum_Off_x")) - nz(join.tbl.("sum_Off_y")))
      join.select({"Route_Name", "Agency_x", "sum_On_x", "sum_Off_x", "sum_On_y", "sum_Off_y", "Delta_On", "Delta_Off"})

      names = join.colnames()
      for name in names do
          if Left(name, 4) = "sum_" then do
              new_name = Substitute(name, "sum_", "", 1)
              new_name = Substitute(new_name, "x", s1_name, 1)
              new_name = Substitute(new_name, "y", s2_name, 1)
              join.rename(name, new_name)
          end
      end
      
      join.write_csv(S1_tod_dir + "/boardings_alightings_byroute_" + TOD + ".csv")

      //by agency
      df_S1.group_by("Agency")
      df_S1.summarize({"sum_On", "sum_Off"}, "sum")
      df_S2.group_by("Agency")
      df_S2.summarize({"sum_On", "sum_Off"}, "sum")

      join = df_S1.outer_join(df_S2, "Agency", "Agency")
      join.mutate("Delta_On", nz(join.tbl.("sum_sum_On_x")) - nz(join.tbl.("sum_sum_On_y"))) 
      join.mutate("Delta_Off", nz(join.tbl.("sum_sum_Off_x")) - nz(join.tbl.("sum_sum_Off_y")))

      names = join.colnames()
      for name in names do
          if Left(name, 4) = "sum_" then do
              new_name = Substitute(name, "sum_", "", 1)
              new_name = Substitute(new_name, "sum_", "", 1) //some fields start with sum_sum_
              new_name = Substitute(new_name, "x", s1_name, 1)
              new_name = Substitute(new_name, "y", s2_name, 1)
              join.rename(name, new_name)
          end
      end
      join.write_csv(S1_tod_dir + "/boardings_alightings_byagency_" + TOD + ".csv")

      //4.2.2 passenger miles and hours by route and agency
      df_S1 = null 
      df_S1 = CreateObject("df", s1_pmilefile)
      df_S1.group_by("route")
      df_S1.summarize({"pass_hours", "pass_miles"}, "sum")
      df_S1.left_join(df_s1_rts, "route", "Route_ID")

      df_S2 = null 
      df_S2 = CreateObject("df", s2_pmilefile)
      df_S2.group_by("route")
      df_S2.summarize({"pass_hours", "pass_miles"}, "sum")
      df_S2.left_join(df_s2_rts, "route", "Route_ID")

      join = df_S1.outer_join(df_S2, "Route_Name", "Route_Name")
      join.mutate("Delta_hours", nz(join.tbl.("sum_pass_hours_x")) - nz(join.tbl.("sum_pass_hours_y")))
      join.mutate("Delta_miles", nz(join.tbl.("sum_pass_miles_x")) - nz(join.tbl.("sum_pass_miles_y")))
      join.select({"Route_Name", "Agency_x", "sum_pass_hours_x", "sum_pass_miles_x", "sum_pass_hours_y", "sum_pass_miles_y", "Delta_hours", "Delta_miles"})
      
      names = join.colnames()
      for name in names do
          if Left(name, 4) = "sum_" then do
              new_name = Substitute(name, "sum_", "", 1)
              new_name = Substitute(new_name, "x", s1_name, 1)
              new_name = Substitute(new_name, "y", s2_name, 1)
              join.rename(name, new_name)
          end
      end

      //by route
      join.write_csv(S1_output_dir + "/passhoursandmiles_byroute_daily.csv")

      //by agency
      df_S1.group_by("Agency")
      df_S1.summarize({"sum_pass_hours", "sum_pass_miles"}, "sum")
      
      df_S2.group_by("Agency")
      df_S2.summarize({"sum_pass_hours", "sum_pass_miles"}, "sum")
      
      join = df_S1.outer_join(df_S2, "Agency", "Agency")
      join.mutate("Delta_hours", nz(join.tbl.("sum_sum_pass_hours_x")) - nz(join.tbl.("sum_sum_pass_hours_y"))) 
      join.mutate("Delta_miles", nz(join.tbl.("sum_sum_pass_miles_x")) - nz(join.tbl.("sum_sum_pass_miles_y")))

      names = join.colnames()
      for name in names do
          if Left(name, 4) = "sum_" then do
              new_name = Substitute(name, "sum_sum_", "", 1)
              new_name = Substitute(new_name, "x", s1_name, 1)
              new_name = Substitute(new_name, "y", s2_name, 1)
              join.rename(name, new_name)
          end
      end
      join.write_csv(S1_output_dir + "/passhoursandmiles_byagency_daily.csv")
      
      //4.3 Create maps
      mapvars = {"Diff_avgwttime", "Diff_access", "Diff_trips", "Diff_access_job", "PctDiff_avgwttime", "PctDiff_access", "PctDiff_trips", "PctDiff_access_job"}
      for varname in mapvars do
          opts = null
          opts.output_dir = S1_tod_dir
          opts.taz_file = taz_file
          opts.varname = varname
          opts.comp_string = comp_string
          opts.tod = TOD
          RunMacro("Create Transit Map", opts)
      end
      
      RunMacro("Close All")
      Return(1)
  end
  else Return(1)
endmacro

Macro "Create Transit Map" (opts)
    output_dir = opts.output_dir 
    taz_file = opts.taz_file
    varname = opts.varname
    comp_string = opts.comp_string
    TOD = opts.tod

    // Mapping VMT delta on a taz map
    {map, {tlyr}} = RunMacro("Create Map", {file: taz_file})
    vw = OpenTable("vw", "CSV", {output_dir + "\\" + comp_string + "_" + TOD + "_comparison.csv", })
    mapFile = output_dir + "\\" + comp_string + "_Comparison_" + varname + "_" + TOD + ".map"
    jnvw = JoinViews("jv", tlyr + ".ID", vw + ".TAZ",)
    SetView(jnvw)

    // Create a theme for var
    numClasses = 4
    opts = null
    opts.[Pretty Values] = "True"
    opts.[Drop Empty Classes] = "True"
    opts.Title = "Change in " + varname + " in " + TOD
    opts.Other = "False"
    opts.[Force Value] = 0
    opts.zero = "TRUE"
    cTheme = CreateTheme(varname, jnvw + "." + varname, "Equal Steps" , numClasses, opts)

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
    title = comp_string + " Comparison in " + varname
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
    SaveMap(map, mapFile)
    CloseMap(map)

endmacro

