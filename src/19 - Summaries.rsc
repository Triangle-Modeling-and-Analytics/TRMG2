/*
After the model is finished, these macros summarize the results into maps
and tables.
*/

Macro "Summaries" (Args)

    RunMacro("Load Link Layer", Args)
    RunMacro("Calculate Daily Fields", Args)
    RunMacro("Create Count Difference Map", Args)
    RunMacro("Count PRMSEs", Args)
    RunMacro("VOC Maps", Args)
    RunMacro("Speed Maps", Args)
    RunMacro("Summarize HB DC and MC", Args)
    RunMacro("Summarize NM", Args)
    RunMacro("Summarize by FT and AT", Args)
    RunMacro("Transit Summary", Args)

    return(1)
endmacro

/*
This loads the final assignment results onto the link layer.
*/

Macro "Load Link Layer" (Args)

    hwy_dbd = Args.Links
    assn_dir = Args.[Output Folder] + "\\assignment\\roadway\\"
    periods = Args.periods

    {nlyr, llyr} = GetDBLayers(hwy_dbd)

    for period in periods do
        assn_file = assn_dir + "\\roadway_assignment_" + period + ".bin"

        vw = OpenTable("temp", "FFB", {assn_file})
        {field_names, } = GetFields(vw, "All")
        CloseView(vw)
        RunMacro("Join Table To Layer", hwy_dbd, "ID", assn_file, "ID1")
        {map, {nlyr, llyr}} = RunMacro("Create Map", {file: hwy_dbd})
        for field_name in field_names do
            if field_name = "ID1" then continue
            // Remove the field if it already exists before renaming
            RunMacro("Remove Field", llyr, field_name + "_" + period)
            RunMacro("Rename Field", llyr, field_name, field_name + "_" + period)
        end

        // Calculate delay by time period and direction
        a_dirs = {"AB", "BA"}
        for dir in a_dirs do

            // Add delay field
            delay_field = dir + "_Delay_" + period
            a_fields = {{
                delay_field, "Real", 10, 2,,,,
                "Hours of Delay|(CongTime - FFTime) * Flow / 60"
            }}
            RunMacro("Add Fields", {view: llyr, a_fields: a_fields})

            // Get data vectors
            v_fft = nz(GetDataVector(llyr + "|", "FFTime", ))
            v_ct = nz(GetDataVector(llyr + "|", dir + "_Time_" + period, ))
            v_vol = nz(GetDataVector(llyr + "|", dir + "_Flow_" + period, ))

            // Calculate delay
            v_delay = (v_ct - v_fft) * v_vol / 60
            v_delay = max(v_delay, 0)
            SetDataVector(llyr + "|", delay_field, v_delay, )
        end

        // LOSD is used for V/C maps. Calculate this.
        for dir in a_dirs do
            field = dir + "_VOC_" + period
            e_field = dir + "_VOCE_" + period
            d_field = dir + "_VOCD_" + period

            // Rename the original field and add a description
            RunMacro("Rename Field", llyr, field, e_field)
            RunMacro("Add Field Description", llyr, e_field, "V/C based on LOS E")

            // Add and calculate the new field (los d)
            a_fields = {{d_field, "Real", 10, 3,,,,"V/C based on LOS D"}}
            RunMacro("Add Fields", {view: llyr, a_fields: a_fields})
            v_flow = GetDataVector(llyr + "|", dir + "_FLOW_PCE_" + period, )
            v_cap = GetDataVector(llyr + "|", dir + period + "CapD", )
            v_vc = v_flow / v_cap
            array.(d_field) = v_vc
        end
        SetDataVectors(llyr + "|", array, )

        CloseMap(map)
    end
endmacro

/*
This macro summarize fields across time period and direction.

The loaded network table will have a volume field for each class that looks like
"AB_Flow_auto_AM". It will also have fields aggregated across classes that look
like "BA_Flow_PM" and "AB_VMT_MD". Direction (AB/BA) and time period (e.g. AM)
will be looped over. Create an array of the rest of the field names to
summarize. e.g. {"Flow_auto", "Flow", "VMT"}.
*/

Macro "Calculate Daily Fields" (Args)

  a_periods = Args.periods
  loaded_dbd = Args.Links
  a_dir = {"AB", "BA"}
  modes = {"sov", "hov2", "hov3", "CV", "SUT", "MUT"}

  // Add link layer to workspace
  {nlyr, llyr} = GetDBLayers(loaded_dbd)
  llyr = AddLayerToWorkspace(llyr, loaded_dbd, llyr)

  // Calculate non-additive daily fields
  fields_to_add = {
    {"AB_Speed_Daily", "Real", 10, 2,,,, "Slowest speed throughout day"},
    {"BA_Speed_Daily", "Real", 10, 2,,,, "Slowest speed throughout day"},
    {"AB_Time_Daily", "Real", 10, 2,,,, "Highest time throughout day"},
    {"BA_Time_Daily", "Real", 10, 2,,,, "Highest time throughout day"},
    {"AB_VOCE_Daily", "Real", 10, 2,,,, "Highest LOS E v/c throughout day"},
    {"BA_VOCE_Daily", "Real", 10, 2,,,, "Highest LOS E v/c throughout day"},
    {"AB_VOCD_Daily", "Real", 10, 2,,,, "Highest LOS D v/c throughout day"},
    {"BA_VOCD_Daily", "Real", 10, 2,,,, "Highest LOS D v/c throughout day"}
  }
  RunMacro("Add Fields", {view: llyr, a_fields: fields_to_add})

  for d = 1 to a_dir.length do
    dir = a_dir[d]

    v_min_speed = GetDataVector(llyr + "|", dir + "_Speed_Daily", )
    v_min_speed = if (v_min_speed = null) then 9999 else v_min_speed
    v_max_time = GetDataVector(llyr + "|", dir + "_Time_Daily", )
    v_max_time = if (v_max_time = null) then 0 else v_max_time
    // LOS E v/c
    v_max_voce = nz(GetDataVector(llyr + "|", dir + "_VOCE_Daily", ))
    // LOS D v/c
    v_max_vocd = nz(GetDataVector(llyr + "|", dir + "_VOCD_Daily", ))

    for p = 1 to a_periods.length do
      period = a_periods[p]

      v_speed = GetDataVector(llyr + "|", dir + "_Speed_" + period, )
      v_time = GetDataVector(llyr + "|", dir + "_Time_" + period, )
      v_voce = GetDataVector(llyr + "|", dir + "_VOCE_" + period, )
      v_vocd = GetDataVector(llyr + "|", dir + "_VOCD_" + period, )

      v_min_speed = min(v_min_speed, v_speed)
      v_max_time = max(v_max_time, v_time)
      v_max_voce = max(v_max_voce, v_voce)
      v_max_vocd = max(v_max_vocd, v_vocd)
    end

    SetDataVector(llyr + "|", dir + "_Speed_Daily", v_min_speed, )
    SetDataVector(llyr + "|", dir + "_Time_Daily", v_max_time, )
    SetDataVector(llyr + "|", dir + "_VOCE_Daily", v_max_voce, )
    SetDataVector(llyr + "|", dir + "_VOCD_Daily", v_max_vocd, )
  end

  // Sum up the flow fields
  for mode in modes do
    if mode = "SUT" then vots = {1, 2, 3}
    else if mode = "MUT" then vots = {1, 2, 3, 4, 5}
    else vots = {2, 3, 4, 5}

    for dir in a_dir do
      out_field = dir + "_" + mode + "_Flow_Daily"
      fields_to_add = fields_to_add + {{out_field, "Real", 10, 2,,,,"Daily " + dir + " " + mode + " Flow"}}
      v_output = null

      // For this direction and mode, sum every combination of VOT and period
      for vot in vots do
        for period in a_periods do
          input_field = dir + "_Flow_" + mode + "_VOT" + String(vot) + "_" + period
          v_add = GetDataVector(llyr + "|", input_field, )
          v_output = nz(v_output) + nz(v_add)
        end
      end

      output.(out_field) = v_output
      output.(dir + "_Flow_Daily") = nz(output.(dir + "_Flow_Daily")) + v_output
      output.Total_Flow_Daily = nz(output.Total_Flow_Daily) + v_output
    end
  end
  fields_to_add = fields_to_add + {
    {"AB_Flow_Daily", "Real", 10, 2,,,,"AB Daily Flow"},
    {"BA_Flow_Daily", "Real", 10, 2,,,,"BA Daily Flow"},
    {"Total_Flow_Daily", "Real", 10, 2,,,,"Daily Flow in both direction"}
  }

  // Other fields to sum
  a_fields = {"VMT", "VHT", "Delay"}
  for field in a_fields do
    for dir in a_dir do
      v_output = null
      out_field = dir + "_" + field + "_Daily"
      fields_to_add = fields_to_add + {{out_field, "Real", 10, 2,,,,"Daily " + dir + " " + field}}
      for period in a_periods do
        input_field = dir + "_" + field + "_" + period
        v_add = GetDataVector(llyr + "|", input_field, )
        v_output = nz(v_output) + nz(v_add)
      end
      output.(out_field) = v_output
      output.("Total_" + field + "_Daily") = nz(output.("Total_" + field + "_Daily")) + v_output
    end

    fields_to_add = fields_to_add + {{"Total_" + field + "_Daily", "Real", 10, 2,,,,"Daily " + field + " in both directions"}}
  end

  RunMacro("Add Fields", {view: llyr, a_fields: fields_to_add})
  SetDataVectors(llyr + "|", output, )
  DropLayerFromWorkspace(llyr)
EndMacro

/*

*/

Macro "Create Count Difference Map" (Args)
  
  output_dir = Args.[Output Folder]
  hwy_dbd = Args.Links

  // Create total count diff map
  opts = null
  opts.output_file = output_dir +
    "/_summaries/maps/Count Difference - Total.map"
  opts.hwy_dbd = hwy_dbd
  opts.count_id_field = "CountID"
  opts.count_field = "DailyCount"
  opts.vol_field = "Total_Flow_Daily"
  opts.field_suffix = "All"
  RunMacro("Count Difference Map", opts)

//   // Create SUT count diff map
//   opts = null
//   opts.output_file = output_dir +
//     "/_summaries/maps/Count Difference - SUT.map"
//   opts.hwy_dbd = hwy_dbd
//   opts.count_id_field = "CountID"
//   opts.count_field = "SUTCount"
//   opts.vol_field = "SUT_Flow_Daily"
//   opts.field_suffix = "SUT"
//   RunMacro("Count Difference Map", opts)

//   // Create MUT count diff map
//   opts = null
//   opts.output_file = output_dir +
//     "/_summaries/maps/Count Difference - MUT.map"
//   opts.hwy_dbd = hwy_dbd
//   opts.count_id_field = "CountID"
//   opts.count_field = "MUTCount"
//   opts.vol_field = "MUT_Flow_Daily"
//   opts.field_suffix = "MUT"
//   RunMacro("Count Difference Map", opts)
EndMacro

/*
Creates tables with %RMSE and volume % diff by facility type and volume group
*/

Macro "Count PRMSEs" (Args)
  hwy_dbd = Args.Links

  opts.hwy_bin = Substitute(hwy_dbd, ".dbd", ".bin", )
  opts.volume_field = "Volume_All"
  opts.count_id_field = "CountID"
  opts.count_field = "Count_All"
  opts.class_field = "HCMType"
  opts.area_field = "AreaType"
  opts.volume_breaks = {10000, 25000, 50000, 100000}
  opts.out_dir = Args.[Output Folder] + "/_summaries/roadway_tables"
  RunMacro("Roadway Count Comparison Tables", opts)
endmacro

/*
Creates V/C maps for each time period and LOS (D and E)
*/

Macro "VOC Maps" (Args)

  hwy_dbd = Args.Links
  periods = Args.periods + {"Daily"}
  output_dir = Args.[Output Folder] + "/_summaries/maps"
  if GetDirectoryInfo(output_dir, "All") = null then CreateDirectory(output_dir)
  levels = {"D", "E"}

  for period in periods do
    for los in levels do

      mapFile = output_dir + "/voc_" + period + "_LOS" + los + ".map"

      //Create a new, blank map
      {map, {nlyr, llyr}} = RunMacro("Create Map", {file: hwy_dbd})
      SetLayerVisibility(map + "|" + nlyr, "false")
      SetLayer(llyr)

      // Dualized Scaled Symbol Theme
      flds = {llyr+".AB_Flow_" + period}
      opts = null
      opts.Title = period + " Flow"
      opts.[Data Source] = "All"
      opts.[Minimum Size] = 1
      opts.[Maximum Size] = 10
      theme_name = CreateContinuousTheme("Flows", flds, opts)
      // Set color to white to make it disappear in legend
      dual_colors = {ColorRGB(65535,65535,65535)}
      dual_linestyles = {LineStyle({{{2, -1, 0},{0,0,1},{0,0,-1}}})}
      dual_linesizes = {0}
      SetThemeLineStyles(theme_name , dual_linestyles)
      SetThemeLineColors(theme_name , dual_colors)
      SetThemeLineWidths(theme_name , dual_linesizes)
      ShowTheme(, theme_name)

      // Apply color theme based on the V/C
      num_classes = 4
      theme_title = if period = "Daily"
        then "Max V/C (LOS " + los + ")"
        else period + " V/C (LOS " + los + ")"
      cTheme = CreateTheme(
        theme_title, llyr+".AB_VOC" + los + "_" + period, "Manual",
        num_classes,
        {
          {"Values",{
            {0.0,"True",0.6,"False"},
            {0.6,"True",0.75,"False"},
            {0.75,"True",0.9,"False"},
            {0.9,"True",100,"False"}
            }},
          {"Other", "False"}
        }
      )

      line_colors =	{
        ColorRGB(10794, 52428, 17733),
        ColorRGB(63736, 63736, 3084),
        ColorRGB(65535, 32896, 0),
        ColorRGB(65535, 0, 0)
      }
      dualline = LineStyle({{{2, -1, 0},{0,0,1},{0,0,-1}}})

      for i = 1 to num_classes do
          class_id = llyr +"|" + cTheme + "|" + String(i)
          SetLineStyle(class_id, dualline)
          SetLineColor(class_id, line_colors[i])
          SetLineWidth(class_id, 2)
      end

      // Change the labels of the classes for legend
      labels = {
        "Congestion Free (VC < .6)",
        "Moderate Traffic (VC .60 to .75)",
        "Heavy Traffic (VC .75 to .90)",
        "Stop and Go (VC > .90)"
      }
      SetThemeClassLabels(cTheme, labels)
      ShowTheme(,cTheme)

      // Hide centroid connectors
      SetLayer(llyr)
      ccquery = "Select * where HCMType = 'CC'"
      n1 = SelectByQuery ("CCs", "Several", ccquery,)
      if n1 > 0 then SetDisplayStatus(llyr + "|CCs", "Invisible")

      // Configure Legend
      SetLegendDisplayStatus(llyr + "|", "False")
      RunMacro("G30 create legend", "Theme")
      subtitle = if period = "Daily"
        then "Daily Flow + Max V/C"
        else period + " Period"
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
      str1 = "XXXXXXXX"
      solid = FillStyle({str1, str1, str1, str1, str1, str1, str1, str1})
      SetLegendOptions (GetMap(), {{"Background Style", solid}})

      // Save map
      RedrawMap(map)
      windows = GetWindows("Map")
      window = windows[1][1]
      RestoreWindow(window)
      SaveMap(map, mapFile)
      CloseMap(map)
    end
  end
EndMacro

/*
Creates a map showing speed reductions (similar to Google) for each period
*/

Macro "Speed Maps" (Args)

  hwy_dbd = Args.Links
  periods = Args.periods
  output_dir = Args.[Output Folder] + "/_summaries/maps"
  if GetDirectoryInfo(output_dir, "All") = null then CreateDirectory(output_dir)

  for period in periods do

    mapFile = output_dir + "/speed_" + period + ".map"

    //Create a new, blank map
    {map, {nlyr, llyr}} = RunMacro("Create Map", {file: hwy_dbd})
    SetLayerVisibility(map + "|" + nlyr, "false")
    SetLayer(llyr)

    // Dualized Scaled Symbol Theme
    flds = {llyr+".AB_Flow_" + period}
    opts = null
    opts.Title = period + " Flow"
    opts.[Data Source] = "All"
    opts.[Minimum Size] = 1
    opts.[Maximum Size] = 10
    theme_name = CreateContinuousTheme("Flows", flds, opts)
    // Set color to white to make it disappear in legend
    SetThemeLineColors(theme_name , {ColorRGB(65535,65535,65535)})
    dual_linestyles = {LineStyle({{{1, -1, 0}}})}
    SetThemeLineStyles(theme_name , dual_linestyles)
    ShowTheme(, theme_name)

    // Apply color theme based on the % speed reduction
    ab_expr_field = CreateExpression(
      llyr, "ABSpeedRedux",
      "min((AB_Speed_" + period + " - PostedSpeed) / PostedSpeed * 100, 0)",
      {Type: "Real", Decimals: 0}
    )
    ba_expr_field = CreateExpression(
      llyr, "BASpeedRedux",
      "min((BA_Speed_" + period + " - PostedSpeed) / PostedSpeed * 100, 0)",
      {Type: "Real", Decimals: 0}
    )
    num_classes = 5
    theme_title = period + " Speed Reduction %"
    cTheme = CreateTheme(
      theme_title, llyr + "." + ab_expr_field, "Manual",
      num_classes,
      {
        {"Values",{
          {-10,"True", 100,"True"},
          {-20,"True", -10,"False"},
          {-35,"True", -20,"False"},
          {-50,"True", -35,"False"},
          {-100,"True", -50,"False"}
          }}
      }
    )
    line_colors =	{
      ColorRGB(6682, 38550, 16705),
      ColorRGB(42662, 55769, 27242),
      ColorRGB(65535, 65535, 49087),
      ColorRGB(65021, 44718, 24929),
      ColorRGB(55255, 6425, 7196)
    }
    // dualline = LineStyle({{{2, -1, 0},{0,0,1},{0,0,-1}}})
    dualline = LineStyle({{{1, -1, 0}}})

    for i = 1 to num_classes do
        class_id = llyr +"|" + cTheme + "|" + String(i + 1) // 1 is the other class
        SetLineStyle(class_id, dualline)
        SetLineColor(class_id, line_colors[i])
        SetLineWidth(class_id, 2)
    end

    // Change the labels of the classes for legend
    labels = {
      "Other",
      "Reduction < 10%",
      "Reduction < 20%",
      "Reduction < 35%",
      "Reduction < 50%",
      "Reduction > 50%"
    }
    SetThemeClassLabels(cTheme, labels)
    ShowTheme(,cTheme)

    // Hide centroid connectors
    SetLayer(llyr)
    ccquery = "Select * where HCMType = 'CC'"
    n1 = SelectByQuery ("CCs", "Several", ccquery,)
    if n1 > 0 then SetDisplayStatus(llyr + "|CCs", "Invisible")

    // Configure Legend
    SetLegendDisplayStatus(llyr + "|", "False")
    RunMacro("G30 create legend", "Theme")
    subtitle = period + " Period"
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
    str1 = "XXXXXXXX"
    solid = FillStyle({str1, str1, str1, str1, str1, str1, str1, str1})
    SetLegendOptions (GetMap(), {{"Background Style", solid}})

    // Save map
    RedrawMap(map)
    windows = GetWindows("Map")
    window = windows[1][1]
    RestoreWindow(window)
    SaveMap(map, mapFile)
    CloseMap(map)
  end
EndMacro

/*
Creates a table of statistics and writes out
final tables to CSV.
*/

Macro "Summarize HB DC and MC" (Args)

  periods = Args.periods
  taz_file = Args.TAZs
  scen_dir = Args.[Scenario Folder]
  trip_dir = scen_dir + "/output/resident/trip_matrices"
  output_dir = scen_dir + "/output/_summaries/dc"
  skim_dir = scen_dir + "/output/skims/roadway"
  if GetDirectoryInfo(output_dir, "All") = null then CreateDirectory(output_dir)

  mtx_files = RunMacro("Catalog Files", trip_dir, "mtx")

  // Create table of statistics
  df = RunMacro("Matrix Stats", mtx_files)
  df.mutate("period", Right(df.tbl.matrix, 2))
  df.mutate("matrix", Substitute(df.tbl.matrix, "pa_per_trips_", "", ))
  v = Substring(df.tbl.matrix, 1, StringLength(df.tbl.matrix) - 3)
  df.mutate("matrix", v)
  df.rename({"matrix", "core"}, {"trip_type", "mode"})
  df.select({"trip_type", "period", "mode", "Sum", "SumDiag", "PctDiag"})
  df.filter("mode <> 'all_transit'")
  modal_file = output_dir + "/hb_trip_stats_by_modeperiod.csv"
  df.write_csv(modal_file)

  // Summarize by mode
  mc_dir = scen_dir + "/output/_summaries/mc"
  df = CreateObject("df", modal_file)
  df.group_by({"trip_type", "mode"})
  df.summarize("Sum", "sum")
  df.rename("sum_Sum", "Sum")
  df_tot = df.copy()
  df_tot.group_by({"trip_type"})
  df_tot.summarize("Sum", "sum")
  df_tot.rename("sum_Sum", "total")
  df.left_join(df_tot, "trip_type", "trip_type")
  df.mutate("pct", round(df.tbl.Sum / df.tbl.total * 100, 2))
  df.write_csv(output_dir + "/hb_trip_mode_shares.csv")

  // Create a totals matrix for each trip type
  trip_types = RunMacro("Get HB Trip Types", Args)
  for trip_type in trip_types do
    total_file = output_dir + "/" + trip_type + ".mtx"
    total_files = total_files + {total_file}

    for period in periods do
      in_file = trip_dir + "/pa_per_trips_" + trip_type + "_" + period + ".mtx"
      if period = periods[1] then do
        CopyFile(in_file, total_file)
        total_mtx = CreateObject("Matrix", total_file)
        to_drop = total_mtx.GetCoreNames()
        total_mtx.AddCores({"total"})
        total_mtx.DropCores(to_drop)
        total_core = total_mtx.GetCore("total")
        total_core := 0
      end

      in_mtx = CreateObject("Matrix", in_file)
      core_names = in_mtx.GetCoreNames()
      for core_name in core_names do
        if core_name = "all_transit" then continue
        in_core = in_mtx.GetCore(core_name)
        total_core := total_core + nz(in_core)
      end
    end
  end
  total_mtx = null
  total_core = null

  // Summarize totals matrices
  df = RunMacro("Matrix Stats", total_files)
  df.select({"matrix", "core", "Sum", "SumDiag", "PctDiag"})
  stats_file = output_dir + "/hb_trip_stats_by_type.csv"
  df.write_csv(stats_file)

  // Calculate TLFDs
  skim_mtx_file = skim_dir + "/skim_hov_AM.mtx"
  skim_mtx = CreateObject("Matrix", skim_mtx_file)
  skim_core = skim_mtx.GetCore("Length (Skim)")
  for mtx_file in total_files do
    out_mtx_file = Substitute(mtx_file, ".mtx", "_tlfd.mtx", )
    mtx = CreateObject("Matrix", mtx_file)
    trip_core = mtx.GetCore("total")

    tld = CreateObject("Distribution.TLD")
    tld.StartValue = 0
    tld.BinSize = 1
    tld.TripMatrix = trip_core
    tld.ImpedanceMatrix = skim_core
    tld.OutputMatrix(out_mtx_file)
    tld.Run()
    res = tld.GetResults()
    avg_length = res.Data.AvTripLength
    trip_lengths = trip_lengths + {avg_length}
  end
  mtx = null
  trip_core = null

  df = CreateObject("df", stats_file)
  df.mutate("avg_length_mi", A2V(trip_lengths))
  df.write_csv(stats_file)

  // Cluster-2-Cluster flows
  cluster_dir = output_dir + "/cluster_flows"
  RunMacro("Create Directory", cluster_dir)
  {map, {tlyr}} = RunMacro("Create Map", {file: taz_file})
  for mtx_file in total_files do
    
    // Agg matrix to cluster level
    mtx = CreateObject("Matrix", mtx_file)
    core_names = mtx.GetCoreNames()
    core = mtx.GetCore(core_names[1])
    {, , name, } = SplitPath(mtx_file)
    agg_file = cluster_dir + "/" + name + "_c2c.mtx"
    opts = null
    opts.[File Name] = agg_file
    opts.Label = "Cluster Flows"
    mtx_agg = AggregateMatrix(
      core,
      {tlyr + ".ID", tlyr + ".Cluster"},
      {tlyr + ".ID", tlyr + ".Cluster"},
      opts
    )
    mtx_agg = null
    mtx = null
    core = null
  end

  // Remove the totals matrices to save space
  for file in total_files do
    DeleteFile(file)
  end
EndMacro

/*

*/

Macro "Summarize NM" (Args, trip_types)
  
  out_dir = Args.[Output Folder]
  
  per_dir = out_dir + "/resident/population_synthesis"
  per_file = per_dir + "/Synthesized_Persons.bin"
  per_vw = OpenTable("per", "FFB", {per_file})
  nm_dir = out_dir + "/resident/nonmotorized"
  nm_file = nm_dir + "/_agg_nm_trips_daily.bin"
  nm_vw = OpenTable("nm", "FFB", {nm_file})

  summary_file = out_dir + "/_summaries/nm_summary.csv"
  f = OpenFile(summary_file, "w")
  WriteLine(f, "trip_type,moto_total,moto_share,nm_total,nm_share")

  if trip_types = null then trip_types = RunMacro("Get HB Trip Types", Args)
  for trip_type in trip_types do
    moto_v = GetDataVector(per_vw + "|", trip_type, )
    moto_total = VectorStatistic(moto_v, "Sum", )
    if trip_type = "W_HB_EK12_All" then do
      moto_share = 100
      nm_total = 0
      nm_share = 0
    end else do
      nm_v = GetDataVector(nm_vw + "|", trip_type, )
      nm_total = VectorStatistic(nm_v, "Sum", )
      moto_share = round(moto_total / (moto_total + nm_total) * 100, 2)
      nm_share = round(nm_total / (moto_total + nm_total) * 100, 2)
    end

    WriteLine(f, trip_type + "," + String(moto_total) + "," + String(moto_share) + "," + String(nm_total) + "," + String(nm_share))
  end

  CloseView(per_vw)
  CloseView(nm_vw)
  CloseFile(f)
endmacro

/*
Summarize highway stats like VMT and VHT
*/

Macro "Summarize by FT and AT" (Args)

  opts.hwy_dbd = Args.Links
  out_dir = Args.[Output Folder]
  opts.output_dir = out_dir + "/_summaries/roadway_tables"
  opts.summary_fields = {"Total_Flow_Daily", "Total_VMT_Daily", "Total_VHT_Daily", "Total_Delay_Daily"}
  RunMacro("Link Summary by FT and AT", opts)

  RunMacro("Close All")
EndMacro

/*
Summarizes transit assignment.
*/

Macro "Transit Summary" (Args)
  
  scen_dir = Args.[Scenario Folder]
  out_dir  =Args.[Output Folder]
  assn_dir = out_dir + "/assignment/transit"
  
  opts = null
  RunMacro("Summarize Transit", {
    transit_asn_dir: assn_dir,
    output_dir: out_dir + "/_summaries/transit",
    loaded_network: Args.Links
  })
EndMacro