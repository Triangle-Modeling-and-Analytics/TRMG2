/*
After the model is finished, these macros summarize the results into maps
and tables.
*/

Macro "Maps" (Args)
    
    RunMacro("Load Link Layer", Args)
    RunMacro("Calculate Daily Fields", Args)
    RunMacro("Transit Summary", Args)
    RunMacro("Create Count Difference Map", Args)
    RunMacro("VOC Maps", Args)
    RunMacro("Transit Maps", Args)
    RunMacro("Speed Maps", Args)
    //RunMacro("Isochrones", Args)
	  RunMacro("Accessibility Maps", Args)
    
    return(1)
endmacro

Macro "Calibration Reports" (Args)
    
    RunMacro("Count PRMSEs", Args)
    
    return(1)
endmacro

Macro "Other Reports" (Args)
    
    RunMacro("Summarize HB DC and MC", Args)
    RunMacro("Summarize NHB DC and MC", Args)
    RunMacro("Summarize NM", Args)
    RunMacro("Summarize Total Mode Shares", Args)
    RunMacro("Summarize Links", Args)
    RunMacro("Congested VMT", Args)
    RunMacro("Summarize Parking", Args)
    RunMacro("VMT_Delay Summary", Args)
    RunMacro("Congestion Cost Summary", Args)
    RunMacro("Create PA Vehicle Trip Matrices", Args)
    RunMacro("Equity", Args)
    RunMacro("Disadvantage Community Skims", Args)
    RunMacro("Disadvantage Community Mode Shares", Args)
    RunMacro("Disadvantage Community Mapping", Args)
    RunMacro("Summarize NM Disadvantage Community", Args)
    RunMacro("Summarize HH Strata", Args)
    RunMacro("Aggregate Transit Flow by Route", Args)
    RunMacro("Validation Reports", Args)
    RunMacro("Export Highway Geodatabase", Args)
    RunMacro("Performance Measures Reports", Args)
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
  fields_to_add = null

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

    for dir in a_dir do
      out_field = dir + "_" + mode + "_Flow_Daily"
      fields_to_add = fields_to_add + {{out_field, "Real", 10, 2,,,,"Daily " + dir + " " + mode + " Flow"}}
      v_output = null

      // For this direction and mode, sum every period
      for period in a_periods do
        input_field = dir + "_Flow_" + mode + "_" + period
        v_add = GetDataVector(llyr + "|", input_field, )
        v_output = nz(v_output) + nz(v_add)
      end

      output.(out_field) = v_output
      output.(dir + "_Flow_Daily") = nz(output.(dir + "_Flow_Daily")) + v_output
      output.Total_Flow_Daily = nz(output.Total_Flow_Daily) + v_output
    end
  end
  output.Total_CV_Flow_Daily = output.AB_CV_Flow_Daily + output.BA_CV_Flow_Daily
  output.Total_SUT_Flow_Daily = output.AB_SUT_Flow_Daily + output.BA_SUT_Flow_Daily
  output.Total_MUT_Flow_Daily = output.AB_MUT_Flow_Daily + output.BA_MUT_Flow_Daily
  fields_to_add = fields_to_add + {
    {"AB_Flow_Daily", "Real", 10, 2,,,,"AB Daily Flow"},
    {"BA_Flow_Daily", "Real", 10, 2,,,,"BA Daily Flow"},
    {"Total_Flow_Daily", "Real", 10, 2,,,,"Daily Flow in both direction"},
    {"Total_CV_Flow_Daily", "Real", 10, 2,,,,"Daily CV Flow in both direction"},
    {"Total_SUT_Flow_Daily", "Real", 10, 2,,,,"Daily SUT Flow in both direction"},
    {"Total_MUT_Flow_Daily", "Real", 10, 2,,,,"Daily MUT Flow in both direction"}
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

	description = "Daily " + field + " in both directions"
	if field = "Delay" then description = description + " (hours)"
    fields_to_add = fields_to_add + {{"Total_" + field + "_Daily", "Real", 10, 2,,,, description}}
  end

  // The assignment files don't have total delay by period. Create those.
  for period in a_periods do
    out_field = "Tot_Delay_" + period
    fields_to_add = fields_to_add + {{out_field, "Real", 10, 2,,,, period + " Total Delay"}}
    {v_ab, v_ba} = GetDataVectors(llyr + "|", {"AB_Delay_" + period, "BA_Delay_" + period}, )
    v_output = nz(v_ab) + nz(v_ba)
    output.(out_field) = v_output
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

  // Create SUT count diff map
  opts = null
  opts.output_file = output_dir +
    "/_summaries/maps/Count Difference - SUT.map"
  opts.hwy_dbd = hwy_dbd
  opts.count_id_field = "CountID"
  opts.count_field = "DailyCountSUT"
  opts.vol_field = "Total_SUT_Flow_Daily"
  opts.field_suffix = "SUT"
  RunMacro("Count Difference Map", opts)

  // Create MUT count diff map
  opts = null
  opts.output_file = output_dir +
    "/_summaries/maps/Count Difference - MUT.map"
  opts.hwy_dbd = hwy_dbd
  opts.count_id_field = "CountID"
  opts.count_field = "DailyCountMUT"
  opts.vol_field = "Total_MUT_Flow_Daily"
  opts.field_suffix = "MUT"
  RunMacro("Count Difference Map", opts)
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
  opts.median_field = "HCMMedian"
  opts.screenline_field = "Cutline"
  opts.volume_breaks = {10000, 25000, 50000, 100000}
  opts.out_dir = Args.[Output Folder] + "/_summaries/validation"
  RunMacro("Roadway Count Comparison Tables", opts)

  // Rename screenline to cutline
  in_file = opts.out_dir + "/count_comparison_by_screenline.csv"
  out_file = opts.out_dir + "/count_comparison_by_cutline.csv"
  if GetFileInfo(out_file) <> null then DeleteFile(out_file)
  RenameFile(in_file, out_file)

  // Run it again to generate the screenline table
  opts.screenline_field = "Screenline"
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

  // The first set of colors are the traditional green-to-red ramp. The second
  // set of colors are yellow-to-blue, which is color-blind friendly.
  a_line_colors =	{
    {
      ColorRGB(10794, 52428, 17733),
      ColorRGB(63736, 63736, 3084),
      ColorRGB(65535, 32896, 0),
      ColorRGB(65535, 0, 0)
    },
    {
      ColorRGB(65535, 65535, 54248),
      ColorRGB(41377, 56026, 46260),
      ColorRGB(16705, 46774, 50372),
      ColorRGB(8738, 24158, 43176)
    }
  }
  color_suffixes = {"GrRd", "YlBu"}

  for j = 1 to 2 do
    line_colors = a_line_colors[j]
    color_suffix = color_suffixes[j]

    for period in periods do
      for los in levels do

        mapFile = output_dir + "/voc_" + period + "_LOS" + los + "_" + color_suffix + ".map"

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
  end
EndMacro

/*
Creates a map showing transit flow
*/

Macro "Transit Maps" (Args)
  
  hwy_dbd = Args.Links
  output_dir = Args.[Output Folder] + "/_summaries/maps"
  if GetDirectoryInfo(output_dir, "All") = null then CreateDirectory(output_dir)

  map = CreateObject("Map", hwy_dbd)
  {nlyr, llyr} = map.GetLayerNames()
  map.SetLayer(llyr)
  map.SizeTheme({
    FieldName: "AB_TransitFlow"
  })
  map.HideLayer(nlyr)
  map.Save(output_dir + "/transit_flow.map")

endmacro

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
      llyr, "AB" + period + "SpeedRedux",
      "min((AB_Speed_" + period + " - PostedSpeed) / PostedSpeed * 100, 0)",
      {Type: "Real", Decimals: 0}
    )
    ba_expr_field = CreateExpression(
      llyr, "BA" + period + "SpeedRedux",
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

*/

Macro "Accessibility Maps" (Args)
	
	taz_file = Args.TAZs
	se_file = Args.SE
	periods = Args.periods
	output_dir = Args.[Output Folder] + "/_summaries/accessibility"
	if GetDirectoryInfo(output_dir, "All") = null then CreateDirectory(output_dir)

	map = CreateObject("Map", taz_file)
	tazs = CreateObject("Table", map.GetActiveLayer())
	se = CreateObject("Table", se_file)
	join = tazs.Join({
		Table: se,
		LeftFields: "ID",
		RightFields: "TAZ"
	})

	a_stats = {
		{field: "access_transit", values: {
			{0, "true", .81, "false"},
			{.81, "true", 2.35, "false"},
			{2.35, "true", 3.49, "false"},
			{3.49, "true", 4.8, "false"},
			{4.8, "true", 1000, "false"}
		}},
		{field: "access_walk", values: {
			{0, "true", .4, "false"},
			{.4, "true", 1.1, "false"},
			{1.1, "true", 1.76, "false"},
			{1.76, "true", 2.61, "false"},
			{2.61, "true", 1000, "false"}
		}}
	}

	for stat in a_stats do
		field = stat.field
		values = stat.values

		map.ColorTheme({
			ThemeName: field,
			FieldName: field,
			Method: "manual",
			NumClasses: ArrayLength(values),
			Options: {
				Values: values,
				Other: "false"
			},
			Colors: {
				StartColor: ColorRGB(65535, 65535, 54248),
				EndColor: ColorRGB(8738, 24158, 43176)
			},
			Labels: {
				"Bad",
				"Poor",
				"Fair",
				"Good",
				"Excellent"
			}
		})
		map.CreateLegend({
			DisplayLayers: "false"
		})

		out_file = output_dir + "/" + field + ".map"
		map.Save(out_file)
	end
endmacro

/*
Creates isochrone (travel time band) maps
*/

Macro "Isochrones" (Args)
  hwy_dbd = Args.Links
  map_dir = Args.[Output Folder] + "\\_summaries\\maps"
  if GetDirectoryInfo(map_dir, "All") = null then CreateDirectory(map_dir)
  iso_dir = map_dir + "\\iso_layers"
  if GetDirectoryInfo(iso_dir, "All") = null then CreateDirectory(iso_dir)
  net_dir = Args.[Output Folder] + "\\networks"
  exclusion_file = Args.[Model Folder] + "\\other\\iso_exclusion\\IsochroneExclusionAreas.cdf"
  
  periods = {"AM"}
  dirs = {"outbound", "inbound"}
  nodes = {
    108108, // Raleigh
    15670,  // Durham
    10827   // RDU
  }
  names = {
    "Raleigh",
    "Durham",
    "RDU"
  }
  
  //Create a new, blank map
  {map, {nlyr, llyr}} = RunMacro("Create Map", {file: hwy_dbd, minimized: "false"})
  SetLayerVisibility(map + "|" + nlyr, "false")
  SetLayer(llyr)

  for period in periods do
    for i = 1 to nodes.length do
      node_id = nodes[i]
      name = names[i]

      SetLayer(nlyr)
      cord = GetPoint(node_id)
      SetLayer(llyr)

      for dir in dirs do
        map_file = map_dir + "\\iso_" + name + "_" + dir + "_" + period + ".map"
        net_file = net_dir + "\\net_" + period + "_sov.net"

        nh = ReadNetwork(net_file)

        o = null
        o = CreateObject("Routing.Bands")
        o.NetworkName = net_file
        o.RoutingLayer = GetLayer()
        o.Minimize = "CongTime"
        o.Interval = 10
        o.BandMax  = 30
        o.CumulativeBands = "Yes"
        o.InboundBands = if dir = "inbound"
          then true
          else false
        o.CreateTheme = true
        o.LoadExclusionAreas(exclusion_file)
        o.CreateBands({
          Coords: {cord},
          FileName: iso_dir + "\\iso_" + name + "_" + dir + "_" + period + ".dbd",
          LayerName : name + " " + dir + " bands"
        })

        RedrawMap(map)
        SaveMap(map_file)
      end
    end
  end

  CloseMap()
endmacro

/*
Creates a table of statistics and writes out
final tables to CSV.

This macro is also used by the scenario comparison tool to re-summarize for
a subarea if one is provided. In that case, Args will have extra options as
shown below:

	* RowIndex and ColIndex
		* Strings
		* If provided, the macro will summarize only a subset of the full matrix. Used
		  by the scenario comparison tool and the disadvantage community (dc) summaries.
	* OutDir
		* String
		* Where to write out the files.
		* Default: Args.[Scenario Folder] + "/output/_summaries/resident_hb"
*/

Macro "Summarize HB DC and MC" (Args)

  periods = Args.periods
  taz_file = Args.TAZs
  scen_dir = Args.[Scenario Folder]
  trip_dir = scen_dir + "/output/resident/trip_matrices"
  output_dir = Args.OutDir
  if output_dir = null then output_dir = scen_dir + "/output/_summaries/resident_hb"
  if GetDirectoryInfo(output_dir, "All") = null then CreateDirectory(output_dir)
  skim_dir = scen_dir + "/output/skims/roadway"
  if GetDirectoryInfo(output_dir, "All") = null then CreateDirectory(output_dir)
  row_index = Args.RowIndex
  col_index = Args.ColIndex
  if row_index <> null or col_index <> null then do
  	index = "true"
	ri = if row_index = null then "All" else row_index
	ci = if col_index = null then "All" else col_index
	index_suffix = ri + "_by_" + ci
  end

  mtx_files = RunMacro("Catalog Files", {dir: trip_dir, ext: "mtx"})

  // Create table of statistics
  df = RunMacro("Matrix Stats", {Matrices: mtx_files, RowIndex: row_index, ColIndex: col_index})
  df.mutate("period", Right(df.tbl.matrix, 2))
  df.mutate("matrix", Substitute(df.tbl.matrix, "pa_per_trips_", "", ))
  v = Substring(df.tbl.matrix, 1, StringLength(df.tbl.matrix) - 3)
  df.mutate("matrix", v)
  df.rename({"matrix", "core"}, {"trip_type", "mode"})
  df.select({"trip_type", "period", "mode", "Sum", "SumDiag", "PctDiag"})
  df.filter("mode contains 'mc_'")
  df.mutate("mode", Substitute(df.tbl.mode, "mc_", "", ))
  if index
    then modal_file = output_dir + "/hb_trip_stats_by_modeperiod_" + index_suffix + ".csv"
    else modal_file = output_dir + "/hb_trip_stats_by_modeperiod.csv"
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
  if index
    then file = output_dir + "/hb_trip_mode_shares_" + index_suffix + ".csv"
    else file = output_dir + "/hb_trip_mode_shares.csv"
  df.write_csv(file)

  // if called by the summary comparison tool, end here
  if index then return()

  // Create a daily/PM matrix for all HB trips
  total_allhb_file = output_dir + "/AllHBTrips.mtx"
  
  // Create a daily matrix for each trip type
  trip_types = RunMacro("Get HB Trip Types", Args)
  for trip_type in trip_types do
    total_file = output_dir + "/" + trip_type + ".mtx"
    total_files = total_files + {total_file}

    if trip_type = trip_types[1] then do
      in_file = trip_dir + "/pa_per_trips_" + trip_type + "_AM.mtx"
      CopyFile(in_file, total_allhb_file)
      total_allhb_mtx = CreateObject("Matrix", total_allhb_file)
      to_drop = total_allhb_mtx.GetCoreNames()
      total_allhb_mtx.AddCores({"total", "PM"})
      total_allhb_mtx.DropCores(to_drop)
      total_allhb_core = total_allhb_mtx.GetCore("total")
      total_allhb_core := 0
      pm_allhb_core = total_allhb_mtx.GetCore("PM")
      pm_allhb_core := 0
    end

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
        if Left(core_name, 3) <> "dc_" then continue // only summarize the dc matrices
        in_core = in_mtx.GetCore(core_name)
        total_core := total_core + nz(in_core)
        total_allhb_core := total_allhb_core + nz(in_core)
        if period = "PM" then pm_allhb_core := pm_allhb_core + nz(in_core)
      end
    end
  end
  total_mtx = null
  total_core = null
  total_allhb_mtx = null
  total_allhb_core = null
  pm_allhb_core = null

  // Summarize totals matrices
  df = RunMacro("Matrix Stats", {Matrices: total_files})
  df.select({"matrix", "core", "Sum", "SumDiag", "PctDiag"})
  stats_file = output_dir + "/hb_trip_stats_by_type.csv"
  df.write_csv(stats_file)

  // Calculate TLFDs
  skim_mtx_file = skim_dir + "/skim_hov_AM.mtx"
  skim_mtx = CreateObject("Matrix", skim_mtx_file)
  skim_coreD = skim_mtx.GetCore("Length (Skim)")
  skim_coreT = skim_mtx.GetCore("CongTime")
  for mtx_file in total_files do
    mtx = CreateObject("Matrix", mtx_file)
    trip_core = mtx.GetCore("total")

    out_mtx_file = Substitute(mtx_file, ".mtx", "_tlfd.mtx", )
    tld = CreateObject("Distribution.TLD")
    tld.StartValue = 0
    tld.BinSize = 1
    tld.TripMatrix = trip_core
    tld.ImpedanceMatrix = skim_coreD
    tld.OutputMatrix(out_mtx_file)
    tld.Run()
    res = tld.GetResults()
    avg_length = res.Data.AvTripLength
    trip_lengths = trip_lengths + {avg_length}

    out_mtx_file = Substitute(mtx_file, ".mtx", "_tlft.mtx", )
    tld = CreateObject("Distribution.TLD")
    tld.StartValue = 0
    tld.BinSize = 1
    tld.TripMatrix = trip_core
    tld.ImpedanceMatrix = skim_coreT
    tld.OutputMatrix(out_mtx_file)
    tld.Run()
    res = tld.GetResults()
    avg_time = res.Data.AvTripLength
    trip_times = trip_times + {avg_time}
  end
  mtx = null
  trip_core = null

  df = CreateObject("df", stats_file)
  df.mutate("avg_length_mi", A2V(trip_lengths))
  df.mutate("avg_time_min", A2V(trip_times))
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
  CloseMap(map)

  // Remove the totals matrices to save space
  // for file in total_files do
  //   DeleteFile(file)
  // end
EndMacro

/*
Summarizes resident non-homebased trips
*/

Macro "Summarize NHB DC and MC" (Args)

  periods = Args.periods
  taz_file = Args.TAZs
  scen_dir = Args.[Scenario Folder]
  trip_dir = scen_dir + "/output/resident/nhb/dc/trip_matrices"
  output_dir = scen_dir + "/output/_summaries/resident_nhb"
  skim_dir = scen_dir + "/output/skims/roadway"
  if GetDirectoryInfo(output_dir, "All") = null then CreateDirectory(output_dir)

  mtx_files = RunMacro("Catalog Files", {dir: trip_dir, ext: "mtx"})

  // Create table of statistics
  df = RunMacro("Matrix Stats", {Matrices: mtx_files})
  df.mutate("period", Right(df.tbl.matrix, 2))
  v_type_orig = Substring(df.tbl.matrix, 1, StringLength(df.tbl.matrix) - 3)
  v_mode = CopyVector(v_type_orig)
  v_type = CopyVector(v_type_orig)
  for i = 1 to v_type.length do
    type = v_type[i]
    parts = ParseString(type, "_")
    mode = parts[parts.length]
    if mode = "pay" then do
      v_mode[i] = "auto_pay"
      v_type[i] = Substitute(type, "_auto_pay", "", )
    end else do
      v_mode[i] = mode
      v_type[i] = Substitute(type, "_" + mode, "", )
    end
  end
  df.mutate("trip_type", v_type)
  df.mutate("mode", v_mode)
  df.filter("core = 'Total'")
  df.select({"trip_type", "period", "mode", "Sum", "SumDiag", "PctDiag"})
  modal_file = output_dir + "/nhb_trip_stats_by_modeperiod.csv"
  df.write_csv(modal_file)

  // Create a daily matrix for each trip type
  v_type = SortVector(v_type_orig, {Unique: "true"})
  for type in v_type do
    daily_file = output_dir + "/" + type + "_daily.mtx"
    daily_files = daily_files + {daily_file}

    for period in periods do
      period_file = trip_dir + "/" + type + "_" + period + ".mtx"

      if period = periods[1] then do
        CopyFile(period_file, daily_file)
        daily_mtx = CreateObject("Matrix", daily_file)
        to_drop = daily_mtx.GetCoreNames()
        daily_mtx.AddCores({"daily"})
        daily_mtx.DropCores(to_drop)
        daily_core = daily_mtx.GetCore("daily")
        daily_core := 0
      end

      period_mtx = CreateObject("Matrix", period_file)
      period_core = period_mtx.GetCore("Total")
      daily_core := daily_core + nz(period_core)
    end
  end
  daily_mtx = null
  daily_core = null

  // Summarize daily matrices
  df = RunMacro("Matrix Stats", {Matrices: daily_files})
  df.select({"matrix", "core", "Sum", "SumDiag", "PctDiag"})
  stats_file = output_dir + "/nhb_trip_stats_by_type.csv"
  df.write_csv(stats_file)

  // Calculate TLFDs
  skim_mtx_file = skim_dir + "/skim_hov_AM.mtx"
  skim_mtx = CreateObject("Matrix", skim_mtx_file)
  skim_coreD = skim_mtx.GetCore("Length (Skim)")
  skim_coreT = skim_mtx.GetCore("CongTime")
  for mtx_file in daily_files do
    {drive, folder, name, ext} = SplitPath(mtx_file)
    mtx = CreateObject("Matrix", mtx_file)
    trip_core = mtx.GetCore("daily")

    out_mtx_file = output_dir + "/" + name + "_tlfd.mtx"
    tld = CreateObject("Distribution.TLD")
    tld.StartValue = 0
    tld.BinSize = 1
    tld.TripMatrix = trip_core
    tld.ImpedanceMatrix = skim_coreD
    tld.OutputMatrix(out_mtx_file)
    tld.Run()
    res = tld.GetResults()
    avg_length = res.Data.AvTripLength
    trip_lengths = trip_lengths + {avg_length}

    out_mtx_file = output_dir + "/" + name + "_tlft.mtx"
    tld = CreateObject("Distribution.TLD")
    tld.StartValue = 0
    tld.BinSize = 1
    tld.TripMatrix = trip_core
    tld.ImpedanceMatrix = skim_coreT
    tld.OutputMatrix(out_mtx_file)
    tld.Run()
    res = tld.GetResults()
    avg_time = res.Data.AvTripLength
    trip_times = trip_times + {avg_time}
  end
  mtx = null
  trip_core = null

  df = CreateObject("df", stats_file)
  df.mutate("avg_length_mi", A2V(trip_lengths))
  df.mutate("avg_time_min", A2V(trip_times))
  df.write_csv(stats_file)

  // Remove the daily matrices to save space
  for file in daily_files do
    DeleteFile(file)
  end
endmacro

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

  summary_file = out_dir + "/_summaries/resident_hb/hb_nm_summary.csv"
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
Combines all travel markets (resident, univ, trucks, etc) into total mode share in the model.
Also called by the scenario comparison tool if a subarea is provided.
*/

Macro "Summarize Total Mode Shares" (Args)
  
  taz_file = Args.TAZs
  scen_dir = Args.[Scenario Folder]
  out_dir = scen_dir + "/output"
  summary_dir = out_dir + "/_summaries"
  periods = Args.periods

  v_auto = RunMacro("Summarize Matrix RowSums", {trip_dir: out_dir + "/assignment/roadway"})
  v_transit = RunMacro("Summarize Matrix RowSums", {trip_dir: out_dir + "/assignment/transit"})
  v_nm = RunMacro("Summarize Matrix RowSums", {trip_dir: out_dir + "/resident/nonmotorized"})
  
  // Get a vector of IDs from one of the matrices
  mtx_files = RunMacro("Catalog Files", {dir: out_dir + "/assignment/roadway", ext: "mtx"})
  mtx = CreateObject("Matrix", mtx_files[1])
  core_names = mtx.GetCoreNames()
  v_id = mtx.GetVector({Core: core_names[1], Index: "Row"})

  // create a table to store results
  tbl = CreateObject("Table", {Fields: {
    {FieldName: "TAZ", Type: "Integer"},
    {FieldName: "county_temp", Type: "String"},
    {FieldName: "auto"},
    {FieldName: "transit"},
    {FieldName: "nm"}
  }})
  tbl.AddRows({EmptyRows: v_id.length})
  tbl.TAZ = v_id
  tbl.auto = v_auto
  tbl.transit = v_transit
  tbl.nm = v_nm
  if subarea then tbl.AddField("subarea")

  // Add county info from the TAZ layer
  taz = CreateObject("Table", taz_file)
  join = tbl.Join({
    Table: taz,
    LeftFields: "TAZ",
    RightFields: "ID"
  })
  join.county_temp = join.County
  if subarea then join.subarea = join.in_subarea
  join = null
  // If a subarea is provided, only summarize those TAZs
  if subarea then do
    tbl.SelectByQuery({
      SetName: "subarea",
      Query: "subarea = 1"
    })
    tbl = tbl.Export()
  end
  if subarea
    then out_file = summary_dir + "/overall_mode_shares_subarea_bytaz.bin"
    else out_file = summary_dir + "/overall_mode_shares_bytaz.bin"
  tbl.Export({FileName: out_file})

  tbl.RenameField({FieldName: "county_temp", NewName: "County"})
  tbl = tbl.Aggregate({
    GroupBy: "County",
    FieldStats: {
      auto: "sum",
      transit: "sum",
      nm: "sum"
    }
  })
  tbl.RenameField({FieldName: "sum_auto", NewName: "auto"})
  tbl.RenameField({FieldName: "sum_transit", NewName: "transit"})
  tbl.RenameField({FieldName: "sum_nm", NewName: "nm"})
  if subarea
    then out_file = summary_dir + "/overall_mode_shares_subarea_bycounty.bin"
    else out_file = summary_dir + "/overall_mode_shares_bycounty.bin"
  tbl.Export({FileName: out_file})
endmacro

/*
Helper macro to 'Sumamrize Total Mode Shares'. Summarize row sums of matrices
and returns a vector.

Inputs
  * trip_dir
    * String
    * The directory holding the matrices to summarize
  * result
    * Vector of summed row totals
*/

Macro "Summarize Matrix RowSums" (MacroOpts)
  
  equiv = MacroOpts.equiv
  trip_dir = MacroOpts.trip_dir
  result = MacroOpts.result

  mtx_files = RunMacro("Catalog Files", {dir: trip_dir, ext: "mtx"})
  counter = 1
  for mtx_file in mtx_files do
    // when summarizing highway matrices, don't include any peak hour matrices,
    // which are already included in the peak period matrices.
    if Right(mtx_file, 8) = "PKHR.mtx" then continue
    mtx = CreateObject("Matrix", mtx_file)
    core_names = mtx.GetCoreNames()
    for core_name in core_names do
      v_row = mtx.GetVector({Core: core_name, Marginal: "Row Sum"})
      if counter = 1
        then result = nz(v_row)
        else result = result + nz(v_row)
      counter = counter + 1
    end
  end
  return(result)
endmacro

/*
Summarize highway stats like VMT and VHT
*/

Macro "Summarize Links" (Args)

  hwy_dbd = Args.Links
  taz_dbd = Args.TAZs
  periods = Args.periods
  periods = periods + {"Daily"}

  // Tag links with various geographies
  {map, {nlyr, llyr}} = RunMacro("Create Map", {file: hwy_dbd})
  {tlyr} = GetDBLayers(taz_dbd)
  tlyr = AddLayer(map, tlyr, taz_dbd, tlyr)
  a_fields =  {
      {"MPO", "Character", 10, ,,,, "The MPO this link is located in"},
      {"County", "Character", 10, ,,,, "The county this link is located in"}
  }
  RunMacro("Add Fields", {view: llyr, a_fields: a_fields})
  TagLayer("Value", llyr + "|", llyr + ".MPO", tlyr + "|", tlyr + ".MPO")
  TagLayer("Value", llyr + "|", llyr + ".County", tlyr + "|", tlyr + ".County")
  SetLayer(llyr)
  fields = {"MPO", "County"}
  for field in fields do
    query = "Select * where " + field + " = null"
    n = SelectByQuery("missing", "several", query)
    if n = 0 then continue
    query2 = "Select * where " + field + " <> null"
    n = SelectByQuery("not missing", "several", query2)
    TagLayer("Value", llyr + "|missing", llyr + "." + field, llyr + "|not missing", llyr + "." + field)
  end
  CloseMap(map)

  opts.hwy_dbd = hwy_dbd
  out_dir = Args.[Output Folder] + "/_summaries/roadway_tables"
  if GetDirectoryInfo(out_dir, "All") = null then CreateDirectory(out_dir)
  for period in periods do
    
    if period = "Daily"
      then total = "Total"
      else total = "Tot"
    
    // opts.summary_fields = {total + "_Flow_" + period, "Total_VMT_Daily", "Total_VHT_Daily", "Total_Delay_Daily"}
    opts.summary_fields = {total + "_Flow_" + period, total + "_VMT_" + period, total + "_VHT_" + period, total + "_Delay_" + period}
    grouping_fields = {"AreaType", "MPO", "County"}
    for grouping_field in grouping_fields do
      opts.output_csv = out_dir + "/Link_Summary_by_FT_and_" + grouping_field + "_" + period + ".csv"
      opts.grouping_fields = {"HCMType", grouping_field}
      RunMacro("Link Summary", opts)
      // Calculate space-mean-speed
      df = CreateObject("df")
      df.read_csv(opts.output_csv)
      v_vmt = df.tbl.("sum_" + total + "_VMT_" + period)
      v_vht = df.tbl.("sum_" + total + "_VHT_" + period)
      df.mutate("SpaceMeanSpeed", v_vmt / v_vht)
      df.write_csv(opts.output_csv)
    end
  end
EndMacro

/*
Calculates the percent of VMT that is congested
*/

Macro "Congested VMT" (Args)
  
  hwy_dbd = Args.Links
  periods = Args.periods
  out_dir = Args.[Output Folder] + "/_summaries/roadway_tables"

  // The V/C ratio that defines the cutoff for congestion.
  vc_cutoff = .75

  // Calculate congested VMT on each link
  {map, {nlyr, llyr}} = RunMacro("Create Map", {file: hwy_dbd})
  for period in Args.periods do
    fields_to_add = fields_to_add + {
		{
			"ABCongLength_" + period, "Real", 10, 2,,,, "The length of link if the " + period +
		  	" period is congested (v/c > " + String(vc_cutoff) + ")|Used by summary macros to skim congested VMT."
		},
		{
			"BACongLength_" + period, "Real", 10, 2,,,, "The length of link if the " + period +
		  	" period is congested (v/c > " + String(vc_cutoff) + ")|Used by summary macros to skim congested VMT."
		},
		{"CongestedVMT_" + period, "Real", 10, ,,,, "The VMT in the " + period + " period that is congested"}
	}
    
    v_length = GetDataVector(llyr + "|", "Length", )
    v_ab_vc = GetDataVector(llyr + "|", "AB_VOCE_" + period, )
    v_ba_vc = GetDataVector(llyr + "|", "BA_VOCE_" + period, )
    v_ab_vmt = GetDataVector(llyr + "|", "AB_VMT_" + period, )
    v_ba_vmt = GetDataVector(llyr + "|", "BA_VMT_" + period, )
    v_ab_cong_vmt = if v_ab_vc > vc_cutoff then v_ab_vmt else 0
    v_ba_cong_vmt = if v_ba_vc > vc_cutoff then v_ba_vmt else 0
    output.("ABCongLength_" + period) = if v_ab_vc > vc_cutoff then v_length else 0
	output.("BACongLength_" + period) = if v_ba_vc > vc_cutoff then v_length else 0
    output.("CongestedVMT_" + period) = v_ab_cong_vmt + v_ba_cong_vmt
  end
  RunMacro("Add Fields", {view: llyr, a_fields: fields_to_add})
  SetDataVectors(llyr + "|", output, )
  CloseMap(map)

  // Summarize links
  for period in periods do
    opts.summary_fields = opts.summary_fields + {"CongestedVMT_" + period, "Tot_VMT_" + period}
  end
  opts.hwy_dbd = hwy_dbd
  grouping_fields = {"MPO", "County"}
  for grouping_field in grouping_fields do
    opts.output_csv = out_dir + "/Congested_VMT_by_" + grouping_field + ".csv"
    opts.grouping_fields = {grouping_field}
    opts.filter = "HCMType <> 'CC'"
    RunMacro("Link Summary", opts)

    df = CreateObject("df")
    df.read_csv(opts.output_csv)
    for field in df.colnames() do
      if Left(field, 4) = "sum_" then do
        new_field = Substitute(field, "sum_", "", )
        df.rename(field, new_field)
      end
    end
    
    v_cong_daily = 0
    v_tot_daily = 0
    for period in periods do
      v_cong = df.tbl.("CongestedVMT_" + period)
      v_tot = df.tbl.("Tot_VMT_" + period)
      v_pct = Round(v_cong / v_tot * 100, 2)
      df.mutate("PctCongestedVMT_" + period, v_pct)

      v_cong_daily = v_cong_daily + v_cong
      v_tot_daily = v_tot_daily + v_tot
    end
    v_pct_daily = Round(v_cong_daily / v_tot_daily * 100, 2)
    df.mutate("PctCongestedVMT_Daily", v_pct_daily)
    df.write_csv(opts.output_csv)
  end
endmacro

/*
Summarizes transit assignment.
*/

Macro "Transit Summary" (Args)
  
  scen_dir = Args.[Scenario Folder]
  out_dir  = Args.[Output Folder]
  assn_dir = out_dir + "/assignment/transit"
  
  opts = null
  RunMacro("Summarize Transit", {
    transit_asn_dir: assn_dir,
    TransModeTable: Args.TransModeTable,
    output_dir: out_dir + "/_summaries/transit",
    loaded_network: Args.Links,
    scen_rts: Args.Routes

  })
EndMacro

Macro "Summarize Parking"  (Args)

  hbmtx_dir = Args.[Output Folder] + "/resident/trip_matrices"
  nhbmtx_dir = Args.[Output Folder] + "/resident/nhb/dc/trip_matrices"
  summary_dir = Args.[Output Folder] + "/_summaries/parking"
  periods = Args.periods

  RunMacro("Create Directory", summary_dir)
  
  mtx_files = RunMacro("Catalog Files", {dir: hbmtx_dir, ext: "mtx"})

  // Create a starting matrix
  out_file = summary_dir + "/parking_daily.mtx"
  CopyFile(mtx_files[1], out_file)
  mtx = CreateObject("Matrix", out_file)
  mh = mtx.GetMatrixHandle()
  RenameMatrix(mh, "Person Trips")
  mh = null
  core_names = mtx.GetCoreNames()
  mtx.AddCores({"parkwalk", "parkshuttle"})
  mtx.DropCores(core_names)
  cores = mtx.GetCores()
  cores.parkwalk := 0
  cores.parkshuttle := 0

  // Collapse the "from park" trips into the daily matrix
  for i = 1 to 2 do
      if i = 2 then mtx_files = RunMacro("Catalog Files", {dir: nhbmtx_dir, ext: "mtx"})
    for mtx_file in mtx_files do
      {drive, path, name, ext} = SplitPath(mtx_file)
      parts = ParseString(name, "_")
      //period = parts[parts.length]
      if parts[2] = "transit" or parts[2] = "walkbike" or parts[3] = "auto" then continue

      in_mtx = CreateObject("Matrix", mtx_file)
      in_cores = in_mtx.GetCores()
      cores.parkwalk := cores.parkwalk + 
        nz(in_cores.sov_parkwalk_frompark) + 
        nz(in_cores.hov2_parkwalk_frompark) + 
        nz(in_cores.hov3_parkwalk_frompark) +
        nz(in_cores.Total_parkwalk_frompark)
      cores.parkshuttle := cores.parkshuttle + 
        nz(in_cores.sov_parkshuttle_frompark) + 
        nz(in_cores.hov2_parkshuttle_frompark) + 
        nz(in_cores.hov3_parkshuttle_frompark) +
        nz(in_cores.Total_parkshuttle_frompark)
    end
  end

  // Replace 0 with null to reduce size
  cores.parkwalk := if cores.parkwalk = 0 then null else cores.parkwalk
  cores.parkshuttle := if cores.parkshuttle = 0 then null else cores.parkshuttle
  cores = null
  mtx.Pack()
endmacro

Macro "VMT_Delay Summary" (Args)

  //Set input file path
  scen_dir = Args.[Scenario Folder]
  scen_outdir = Args.[Output Folder]
  hwy_dbd = Args.Links
  taz_dbd = Args.TAZs
  se_bin = Args.SE
  report_dir = scen_outdir + "\\_summaries" //need to create this dir in argument file 
  output_dir = report_dir + "\\VMT_Delay" //need to create this dir in argument file
  RunMacro("Create Directory", output_dir)
 
  periods = Args.Periods
  a_dirs = {"AB", "BA"}
  veh_classes = {"sov", "hov2", "hov3", "CV", "SUT", "MUT"}
  fields = {"Flow", "VMT", "CgVMT", "Delay"}
  group_fields = {"HCMType", "AreaType", "NCDOTClass", "County", "MPO"}
  
  {map, {nlyr, llyr}} = RunMacro("Create Map", {file: hwy_dbd})

  hwy_df = CreateObject("Table", llyr)

  // Caculate flow, VMT, and delay by direction, period, and vehicle class
  outfield_totcgvmtdailysum = "Total_CgVMT_Daily" // Calculate this total field as it is not included in hwy dbd
  v_totcgvmtdailysum = null

  for veh_class in veh_classes do 
    outfield_totflowdaily = "Flow_"+ veh_class + "_Daily"
    outfield_totvmtdaily = "VMT_"+ veh_class + "_Daily"
    outfield_totcgvmtdaily = "CgVMT_"+ veh_class + "_Daily"
    outfield_totdelaydaily = "Delay_"+ veh_class + "_Daily"
    v_totflowdaily = null
    v_totvmtdaily = null
    v_totcgvmtdaily = null
    v_totdelaydaily = null

    for period in periods do
      outfield_totflow = "Flow_"+ veh_class + "_" + period
      outfield_totvmt = "VMT_" + veh_class + "_" + period
      outfield_totcgvmt = "CgVMT_" + veh_class + "_" + period
      outfield_totdelay = "Delay_" + veh_class + "_" + period      
      v_totflow = null
      v_totvmt = null
      v_totcgvmt = null
      v_totdelay = null

      for dir in a_dirs do
        input_field = dir + "_Flow_" + veh_class + "_" + period
        v_vol = hwy_df.(input_field)

        //flow
        v_totflow = nz(v_totflow) + nz(v_vol)

        //VMT and cgVMT
        length = hwy_df.length
        voc = hwy_df.(dir + "_VOCD_" + period)
        cg_length = if voc >1 then length else 0
        v_totvmt = nz(v_totvmt) + nz(v_vol)*length
        v_totcgvmt = nz(v_totcgvmt) + nz(v_vol)*cg_length

        //delay
        v_fft = hwy_df.FFTime
        v_ct = hwy_df.(dir + "_Time_" + period)
        v_delay = (v_ct - v_fft) * v_vol / 60
        v_delay = max(v_delay, 0)
        v_totdelay = nz(v_totdelay) + nz(v_delay)
      end

      //flow
      hwy_df.AddField(outfield_totflow)
      hwy_df.(outfield_totflow) = v_totflow
      v_totflowdaily = v_totflow + nz(v_totflowdaily)

      //VMT and cgVMT
      hwy_df.AddField(outfield_totvmt)
      hwy_df.(outfield_totvmt) = v_totvmt
      hwy_df.AddField(outfield_totcgvmt)
      hwy_df.(outfield_totcgvmt) = v_totcgvmt
      v_totvmtdaily = nz(v_totvmtdaily) + nz(v_totvmt)
      v_totcgvmtdaily = nz(v_totcgvmtdaily) + nz(v_totcgvmt)

      //delay
      hwy_df.AddField(outfield_totdelay)
      hwy_df.(outfield_totdelay) = v_totdelay
      v_totdelaydaily = nz(v_totdelaydaily) + nz(v_totdelay)
    end
    //flow
    hwy_df.AddField(outfield_totflowdaily)
    hwy_df.(outfield_totflowdaily) = v_totflowdaily

    //VMT and cgVMT
    hwy_df.AddField(outfield_totvmtdaily)
    hwy_df.(outfield_totvmtdaily) = v_totvmtdaily
    hwy_df.AddField(outfield_totcgvmtdaily)
    hwy_df.(outfield_totcgvmtdaily) = v_totcgvmtdaily
    v_totcgvmtdailysum = nz(v_totcgvmtdailysum) + nz(v_totcgvmtdaily)

    //delay
    hwy_df.AddField(outfield_totdelaydaily)
    hwy_df.(outfield_totdelaydaily) = v_totflowdaily
  end
  hwy_df.AddField(outfield_totcgvmtdailysum)
  hwy_df.(outfield_totcgvmtdailysum) = v_totcgvmtdailysum

  // Build summary fields
  periods = periods + {"Daily"}
  for sum_field in fields do
    for veh_class in veh_classes do  
      for period in periods do
        out_field = sum_field + "_" + veh_class + "_" + period
        fields_to_sum = fields_to_sum + {out_field}
      end
    end
  end

  fields_to_sum = fields_to_sum + {"Total_Flow_Daily", "Total_VMT_Daily", "Total_CgVMT_Daily", "Total_VHT_Daily", "Total_Delay_Daily"}
  field_out = {"ID"} + group_fields + fields_to_sum
  hwy_df.SelectByQuery({
    SetName: "to_export",
    Query: "HCMType <> 'TransitOnly' and HCMType <> null and HCMType <> 'CC'"
  })
  hwy_df.Export({FileName: output_dir + "/link_VMT_Delay.csv", FieldNames: field_out})
  CloseMap(map)

  // Summarize by different variable
  group_fields = group_fields + {{"County", "HCMType"}} //add VMT by facility type by county
  FieldStats = null
  for field in fields_to_sum do
    FieldStats.(field) = {"sum", "count"}
  end
  for var in group_fields do
    df = CreateObject("Table", output_dir + "/link_VMT_Delay.csv")
    df = df.Aggregate({
      GroupBy: var,
      FieldStats: FieldStats
    })
    names = df.GetFieldNames()
    for name in names do
        if Left(name, 4) = "sum_" then do
            new_name = Substitute(name, "sum_", "", 1)
            df.RenameField({FieldName: name, NewName: new_name})
        end
    end
    if Typeof(var) = "string" then df.Export({FileName: output_dir + "/VMT_Delay_by_" + var +".csv"})
    else df.Export({FileName: output_dir + "/VMT_Delay_by_HCMType_by_County.csv"})
  end

  // Calculate VMT per capita by MPO/County
  taz_bin = Substitute(taz_dbd, ".dbd", ".bin",)
  taz = CreateObject("Table", taz_bin) // get county info for SE data
  taz_specs = taz.GetFieldSpecs({NamedArray: true})
  se = CreateObject("Table", se_bin)
  se.AddField("POP")
  se.AddField({FieldName: "County", Type: "string"})
  se.AddField({FieldName: "MPO", Type: "string"})
  se_specs = se.GetFieldSpecs({NamedArray: true})
  se.POP = se.HH_POP + se.StudGQ_NCSU + se.StudGQ_UNC + se.StudGQ_DUKE + se.StudGQ_NCCU + se.CollegeOn
  join = se.Join({
    Table: taz,
    LeftFields: "TAZ",
    RightFields: "ID"
  })
  join.(se_specs.County) = join.(taz_specs.County)
  join.(se_specs.MPO) = join.(taz_specs.MPO)
  join = null
  taz = null
  se = null
  group_fields = {"County", "MPO"}
  fields_to_sum = {"HH", "POP"}
  for var in group_fields do 
    df = CreateObject("Table", output_dir + "/link_VMT_Delay.csv")
    df = df.Aggregate({
      GroupBy: var,
      FieldStats: {Total_VMT_Daily: "sum"}
    })
    names = df.GetFieldNames()
    for name in names do
        if Left(name, 4) = "sum_" then do
            new_name = Substitute(name, "sum_", "", 1)
            df.RenameField({FieldName: name, NewName: new_name})
        end
    end
    se = CreateObject("Table", se_bin)
    se = se.Aggregate({
      GroupBy: var,
      FieldStats: {HH: "sum", POP: "sum"}
    })
    names = se.GetFieldNames()
    for name in names do
        if Left(name, 4) = "sum_" then do
            new_name = Substitute(name, "sum_", "", 1)
            se.RenameField({FieldName: name, NewName: new_name})
        end
        if name = "County" or name = "MPO" then do
          new_name = "Geography"
          se.RenameField({FieldName: name, NewName: new_name})
        end
    end
  
    df.AddField("HH")
    df.AddField("POP")
    df.AddField("VMT_per_HH")
    df.AddField("VMT_per_POP")
    df_specs = df.GetFieldSpecs({NamedArray: true})
    se_specs = se.GetFieldSpecs({NamedArray: true})
    join = df.Join({
      Table: se,
      LeftFields: var,
      RightFields: "Geography"
    })
    join.(df_specs.HH) = join.(se_specs.HH)
    join.(df_specs.POP) = join.(se_specs.POP)
    join = null
    df.VMT_per_HH =  df.Total_VMT_Daily/df.HH
    df.VMT_per_POP =  df.Total_VMT_Daily/df.POP

    file_name = GetTempFileName("*.bin")
    df.Export({FileName: file_name})
    to_concat = to_concat + {file_name}
    df = null
    se = null
  end
  out_file = output_dir + "/VMT_perCapita_andHH.bin"
  ConcatenateFiles(to_concat, out_file)
  CopyFile(Substitute(file_name, ".bin", ".dcb",), output_dir + "/VMT_perCapita_andHH.dcb")
  temp = CreateObject("Table", out_file)
  out_file = Substitute(out_file, ".bin", ".csv",)
  temp.Export({FileName: out_file})
  temp = null
  df = CreateObject("Table", out_file)
  names = df.GetFieldNames()

  // Calculate VMT per capita for region
  Total_VMT_Daily = df.Total_VMT_Daily.sum()
  df = null
  se = CreateObject("Table", se_bin)
  HH = se.HH.sum()
  POP = se.POP.sum()
  VMT_per_HH = Total_VMT_Daily/HH
  VMT_per_POP = Total_VMT_Daily/POP
  line = "Regional," + String(Total_VMT_Daily) + "," + String(HH) + "," + String(POP) + "," + String(VMT_per_HH) + "," + String(VMT_per_POP)
  RunMacro("Append Line", {file: out_file, line: line}) //add regional results to output file

  
EndMacro


Macro "Congestion Cost Summary" (Args)
	//Set input file path
	scen_outdir = Args.[Output Folder]
	report_dir = scen_outdir + "\\_summaries" //need to create this dir in argument file 
	output_dir = report_dir + "\\CongestionCost"
	RunMacro("Create Directory", output_dir)

	hwy_dbd = Args.Links
	vot_params = Args.[Input Folder] + "/assignment/vot_params.csv"
	p = RunMacro("Read Parameter File", {file: vot_params})
	periods = Args.Periods
	a_dirs = {"AB", "BA"}
	veh_classes = {"sov", "hov2", "hov3", "CV", "SUT", "MUT"}
	auto_classes = {"sov", "hov2", "hov3", "CV"}
	group_fields = {"HCMType", "AreaType", "NCDOTClass", "County", "MPO"}

	{nLayer, llyr} = GetDBLayers(hwy_dbd)
	llyr = AddLayerToWorkspace(llyr, hwy_dbd, llyr)

  hwy_df = CreateObject("Table", llyr)

	// Calculate CgCost
	for veh_class in veh_classes do
		outfield_daily = "CgCost_" + veh_class + "_Daily"
		v_output_daily = null

		for period in periods do
		outfield = "CgCost_" + veh_class + "_" + period
		v_output = null

		// Determine VOT based on veh type
		if period = "AM" or period = "PM"
			then pkop = "pk"
			else pkop = "op"
		if auto_classes.position(veh_class) > 0 then vot = p.(pkop + "_auto")
		else vot = p.(veh_class)

		for dir in a_dirs do
			// Get data vectors
			v_fft = nz(hwy_df.FFTime)
			v_ct = nz(hwy_df.(dir + "_Time_" + period))
			v_vol = nz(hwy_df.(dir + "_Flow_" + veh_class + "_" + period))

			// Calculate delay
			v_delay = (v_ct - v_fft) * v_vol / 60
			v_delay = max(v_delay, 0)
			v_cost = v_delay * vot

			v_output = nz(v_output) + v_cost
		end  

		v_output_daily = v_output + nz(v_output_daily)
    hwy_df.AddField(outfield)
		hwy_df.(outfield) = v_output
		end
    hwy_df.AddField(outfield_daily)
		hwy_df.(outfield_daily) = v_output_daily
	end

	// Build summary fields
	periods = periods + {"Daily"}
	for veh_class in veh_classes do  
		for period in periods do
			out_field = "CgCost_" + veh_class + "_" + period
			fields_to_sum = fields_to_sum + {out_field}
		end
	end

	field_out = {"ID"} + group_fields + fields_to_sum
  hwy_df.SelectByQuery({
    SetName: "to_export",
    Query: "HCMType <> 'TransitOnly' and HCMType <> null and HCMType <> 'CC'"
  })
  hwy_df.Export({FileName: output_dir + "/LinkCongestionCost.csv", FieldNames: field_out})

	// Summarize by different variable  
  FieldStats = null
  for field in fields_to_sum do
    FieldStats.(field) = {"sum", "count"}
  end
	for var in group_fields do
    cg_df = CreateObject("Table", output_dir + "/LinkCongestionCost.csv")
    cg_df = cg_df.Export({ViewName: "temp"})
    cg_df = cg_df.Aggregate({
      GroupBy: var,
      FieldStats: FieldStats
    })
		names = cg_df.GetFieldNames()
		for name in names do
			if Left(name, 4) = "sum_" then do
				new_name = Substitute(name, "sum_", "", 1)
        cg_df.RenameField({FieldName: name, NewName: new_name})
			end
		end
    cg_df.Export({FileName: output_dir + "/CongestionCost_summary_by_" + var +".csv"})
	end
	CloseView(llyr)
EndMacro

/*
This macro creates aggregate trip matrices that are vehicle
trips but still in PA format. This is useful for various reporting
tools.
*/

Macro "Create PA Vehicle Trip Matrices" (Args)

    // This section is a slight modification to the "HB Occupancy" macro
    factor_file = Args.HBHOV3OccFactors
    periods = Args.periods
    trip_dir = Args.[Output Folder] + "/resident/trip_matrices"
    summary_dir = Args.[Output Folder] + "/_summaries/resident_hb"

    fac_vw = OpenTable("factors", "CSV", {factor_file})
    
    rh = GetFirstRecord(fac_vw + "|", )
    while rh <> null do
        trip_type = fac_vw.trip_type
        period = fac_vw.tod
        hov3_factor = fac_vw.hov3

        if periods.position(period) = 0 then goto skip

        per_mtx_file = trip_dir + "/pa_per_trips_" + trip_type + "_" + period + ".mtx"
        veh_mtx_file = trip_dir + "/pa_veh_trips_" + trip_type + "_" + period + ".mtx"
        CopyFile(per_mtx_file, veh_mtx_file)
        mtx = CreateObject("Matrix", veh_mtx_file)
        cores = mtx.GetCores()
        cores.hov2 := cores.hov2 / 2
        cores.hov3 := cores.hov3 / hov3_factor

        skip:
        rh = GetNextRecord(fac_vw + "|", rh, )
    end
    CloseView(fac_vw)

    // This section is a slight modification to "HB Collapse Trip Types"
    trip_types = RunMacro("Get HB Trip Types", Args)
    auto_cores = {"sov", "hov2", "hov3"}

    for period in periods do

        // Create the final matrix for the period using the first trip type matrix
        mtx_file = trip_dir + "/pa_veh_trips_" + trip_types[1] + "_" + period + ".mtx"
        out_file = summary_dir + "/pa_veh_trips_" + period + ".mtx"
        CopyFile(mtx_file, out_file)
        out_mtx = CreateObject("Matrix", out_file)
        core_names = out_mtx.GetCoreNames()
        for core_name in core_names do
            if auto_cores.position(core_name) = 0 then to_remove = to_remove + {core_name}
        end
        out_mtx.DropCores(to_remove)
        to_remove = null
        out_cores = out_mtx.GetCores()

        // Add the remaining matrices to the output matrix
        for t = 2 to trip_types.length do
            trip_type = trip_types[t]

            mtx_file = trip_dir + "/pa_veh_trips_" + trip_type + "_" + period + ".mtx"
            mtx = CreateObject("Matrix", mtx_file)
            cores = mtx.GetCores()
            for core_name in auto_cores do
                if cores.(core_name) = null then continue
                out_cores.(core_name) := nz(out_cores.(core_name)) + nz(cores.(core_name))
            end
        end

        // Remove interim files
        mtx = null
        cores = null
        out_mtx = null
        out_cores = null
        for trip_type in trip_types do
            mtx_file = trip_dir + "/pa_veh_trips_" + trip_type + "_" + period + ".mtx"
            DeleteFile(mtx_file)
        end
    end
endmacro

/*
Marks the TAZs that meet the various thresholds of disadvantage community. All "coc" below are referring to disadvantage community (dc). 
It's different from how MPOs define coc (communities of concerns).
*/

Macro "Equity" (Args)

	hh_file = Args.Households
	summary_dir = Args.[Output Folder] + "/_summaries/equity"
	se_file = Args.SE
	pov_file = Args.[Input Folder] + "/sedata/poverty_thresholds.csv"

	// Identify which households are zero vehicle, insufficient, and senior
	tbl = CreateObject("Table", hh_file)
	tbl.AddField("v0")
  tbl.AddField("vi")
	tbl.AddField("has_seniors")
	tbl.v0 = if tbl.market_segment = "v0" then 1 else 0
  tbl.vi = if Position(tbl.market_segment, "vi") <> 0 then 1 else 0
	tbl.has_seniors = if tbl.HHSeniors > 0 then 1 else 0
	
	// Identify which households are below poverty thresholds
	pov_tbl = CreateObject("Table", pov_file)
	tbl.AddField("inc_threshold")
	tbl.AddField("temp_senior")
	tbl.AddField("temp_kids")
	tbl.AddField("poverty")
	tbl.temp_senior = if tbl.HHSize > 2 then 0 else tbl.has_seniors
	tbl.temp_kids = if tbl.HHKids > 9 then 9 else tbl.HHKids
	join = tbl.Join({
		Table: pov_tbl,
		LeftFields: {"HHSize", "temp_senior", "temp_kids"},
		RightFields: {"HHSize", "Senior", "Children"}
	})
	join.inc_threshold = join.Threshold
	join = null
	tbl.DropFields({FieldNames: {"temp_kids", "temp_senior"}})
	tbl.poverty = if tbl.HHInc < 1.5 * tbl.inc_threshold then 1 else 0 // if income is lower than 150% of poverty line

	// Summarize by TAZ
	agg = tbl.Aggregate({
		GroupBy: "ZoneID",
		FieldStats: {
			v0: {"count", "sum"},
      vi: {"count", "sum"},
			has_seniors: {"count", "sum"},
			poverty: {"count", "sum"}
		}
	})

	// Calculate zonal metrics
	// v0 CoC
	agg.AddField("v0_pct")
	v_pct = agg.sum_v0 / agg.count_v0 * 100
	agg.v0_pct = v_pct
	cutoff = Percentile(V2A(v_pct), 75)
	agg.AddField("ZeroCar_dc")
	agg.ZeroCar_dc = if agg.v0_pct > cutoff then 1 else 0
	// vi CoC
	agg.AddField("vi_pct")
	v_pct = agg.sum_vi / agg.count_vi * 100
	agg.vi_pct = v_pct
	cutoff = Percentile(V2A(v_pct), 75)
	agg.AddField("VehInsuff_dc")
	agg.VehInsuff_dc = if agg.v0_pct > cutoff then 1 else 0
	// senior CoC
	agg.AddField("senior_pct")
	v_pct = agg.sum_has_seniors / agg.count_has_seniors * 100
	agg.senior_pct = v_pct
	cutoff = Percentile(V2A(v_pct), 75)
	agg.AddField("Senior_dc")
	agg.Senior_dc = if agg.senior_pct > cutoff then 1 else 0
	// poverty CoC
	agg.AddField("poverty_pct")
	v_pct = agg.sum_poverty / agg.count_poverty * 100
	agg.poverty_pct = v_pct
	cutoff = Percentile(V2A(v_pct), 75)
	agg.AddField("Poverty_dc")
	agg.Poverty_dc = if agg.poverty_pct > cutoff then 1 else 0

	// Attach results to SE Data
	if GetDirectoryInfo(summary_dir, "All") = null then CreateDirectory(summary_dir)
	agg.Export({FileName: summary_dir + "/taz_designation.csv"})
	agg.RenameField({FieldName: "ZoneID", NewName: "TAZ"})
	se = CreateObject("Table", se_file)
	se.AddFields({
		Fields: {
			{FieldName: "v0_pct", Description: "Percent of households that are zero-vehicle"},
			{FieldName: "ZeroCar_dc", Description: "TAZ designated as a disadvantage community due to % of v0"},
      {FieldName: "vi_pct", Description: "Percent of households that are vehicle insufficient"},
			{FieldName: "VehInsuff_dc", Description: "TAZ designated as a disadvantage community due to % of vi"},
			{FieldName: "senior_pct", Description: "Percent of households that have seniors"},
			{FieldName: "Senior_dc", Description: "TAZ designated as a disadvantage community due to % of HHs with seniors"},
			{FieldName: "poverty_pct", Description: "Percent of households that are below the poverty threshold"},
			{FieldName: "Poverty_dc", Description: "TAZ designated as a disadvantage community due to % of HHs living in poverty"}
		}
	})
	se_specs = se.GetFieldSpecs({NamedArray: "true"})
	agg_specs = agg.GetFieldSpecs({NamedArray: "true"})
	join = se.Join({
		Table: agg,
		LeftFields: "TAZ",
		RightFields: "TAZ"
	})
	join.(se_specs.v0_pct) = nz(join.(agg_specs.v0_pct))
	join.(se_specs.ZeroCar_dc) = nz(join.(agg_specs.ZeroCar_dc))
  join.(se_specs.vi_pct) = nz(join.(agg_specs.vi_pct))
	join.(se_specs.VehInsuff_dc) = nz(join.(agg_specs.VehInsuff_dc))
	join.(se_specs.senior_pct) = nz(join.(agg_specs.senior_pct))
	join.(se_specs.Senior_dc) = nz(join.(agg_specs.Senior_dc))
	join.(se_specs.poverty_pct) = nz(join.(agg_specs.poverty_pct))
	join.(se_specs.Poverty_dc) = nz(join.(agg_specs.Poverty_dc))
endmacro

/*

*/

Macro "Disadvantage Community Skims" (Args)

	summary_dir = Args.[Output Folder] + "/_summaries/equity"
	net_dir = Args.[Output Folder] + "/networks"
	mtx_dir = Args.[Output Folder] + "/resident/trip_matrices"
	skim_dir = Args.[Output Folder] + "/skims"
	se_file = Args.SE

	// Build a network of AM delay to skim
	net_file = summary_dir + "//net_am.net"
	hwy_dbd = net_dir + "//scenario_links.dbd"
	net = CreateObject("Network.Create")
	net.LayerDB = hwy_dbd
	net.TimeUnits = "Minutes"
	net.LengthField = "Length"
	net.Filter = "D = 1"
	net.AddLinkField({Name: "FFTime", Field: "FFTime", IsTimeField: true})
	net.AddLinkField({Name: "CongTime", Field: {"ABAMTime", "BAAMTime"}, IsTimeField: true})
	net.AddLinkField({Name: "CongLength", Field: {"ABCongLength_AM", "BACongLength_AM"}})
	net.OutNetworkName = net_file
	net.Run()
	net = null
	net = CreateObject("Network.Settings")
	net.LoadNetwork(net_file)
	net.CentroidFilter = "Centroid = 1"
	net.SetPenalties({UTurn: -1})
	net.Run()

	// Skim network
	skim = CreateObject("Network.Skims")
	skim.Network = net_file
	skim.LayerDB = hwy_dbd
	skim.Origins = "Centroid = 1"
	skim.Destinations = "Centroid = 1"
	skim.Minimize = "CongTime"
	skim.AddSkimField({"FFTime", "All"})
	skim.AddSkimField({"CongLength", "All"})
	out_file = summary_dir + "/dc_skim_AM.mtx"
	skim.OutputMatrix({
		MatrixFile: out_file, 
		Matrix: "dc skim"
	})
	ret_value = skim.Run()

	// Calcualte the two trip cores (HBW and All)
	mtx = CreateObject("Matrix", out_file)
	mtx.AddCores({"HBW_Trips", "All_Trips"})
	trip_mtx_file = mtx_dir + "/pa_per_trips_W_HB_W_All_AM.mtx"
	trip_mtx = CreateObject("Matrix", trip_mtx_file)
	mtx.HBW_Trips := trip_mtx.sov + trip_mtx.hov2 + trip_mtx.hov3
	types = RunMacro("Get HB Trip Types", Args)
	for type in types do
		trip_mtx_file = mtx_dir + "/pa_per_trips_" + type + "_AM.mtx"
		trip_mtx = CreateObject("Matrix", trip_mtx_file)
		mtx.All_Trips := nz(mtx.All_Trips) + trip_mtx.sov + trip_mtx.hov2 + trip_mtx.hov3
	end

	// Get transit and walk times which is needed for one of the calculations
	trans_file = skim_dir + "/transit/skim_AM_w_lb.mtx"
	transit_mtx = CreateObject("Matrix", trans_file)
	walk_file = skim_dir + "/nonmotorized/walk_skim.mtx"
	walk_mtx = CreateObject("Matrix", walk_file)
	mtx.AddCores("TransitTime")
	mtx.AddCores("WalkTime")
	mtx.AddCores("NonAutoTime")
	mtx.TransitTime := transit_mtx.("Total Time")
	mtx.WalkTime := walk_mtx.WalkTime
	mtx.NonAutoTime := min(transit_mtx.("Total Time"), walk_mtx.WalkTime)
  mtx.NonAutoTime := if transit_mtx.("Total Time") = null then walk_mtx.WalkTime
	
	// Calcualte the weighted metrics for each CoC
	se = CreateObject("Table", se_file)
	v_emp = se.TotalEmp
	mtx.AddCores({"Employment"})
	mtx.Employment := v_emp
	weight_fields = {"v0_pct", "vi_pct", "senior_pct", "poverty_pct"}
	names = {"ZeroCar", "VehInsuff", "Senior", "Poverty"}
	for i = 1 to weight_fields.length do
    weight_field = weight_fields[i]
    name = names[i]
  
		// Set weight field
		v = se.(weight_field)
		v.rowbased = "false"
		mtx.AddCores({weight_field})
		mtx.(weight_field) := v

		// Calculate hours of travel
		mtx.AddCores({name + "_HBW_HoT", name + "_All_HoT"})
		mtx.(name + "_HBW_HoT") := mtx.CongTime * (mtx.(weight_field) / 100) * mtx.HBW_Trips / 60
		mtx.(name + "_All_HoT") := mtx.CongTime * (mtx.(weight_field) / 100) * mtx.All_Trips / 60

		// Calculate delay
		mtx.AddCores({name + "_HBW_Delay", name + "_All_Delay"})
		mtx.(name + "_HBW_Delay") := (mtx.CongTime - mtx.("FFTime (Skim)")) * (mtx.(weight_field) / 100) * mtx.HBW_Trips / 60
		mtx.(name + "_All_Delay") := (mtx.CongTime - mtx.("FFTime (Skim)")) * (mtx.(weight_field) / 100) * mtx.All_Trips / 60

		// Calculate congested VMT
		mtx.AddCores({name + "_HBW_CongVMT", name + "_All_CongVMT"})
		mtx.(name + "_HBW_CongVMT") := mtx.("CongLength (Skim)") * (mtx.(weight_field) / 100) * mtx.HBW_Trips
		mtx.(name + "_All_CongVMT") := mtx.("CongLength (Skim)") * (mtx.(weight_field) / 100) * mtx.All_Trips

		// Jobs within X minutes (auto, transit, and walk). Also fill the SE table with the row sums for mapping.
		time_budget = 30
    a_data = {
      {TimeCore: "CongTime", OutCoreSuffix: "auto", DescSuffix: "auto"},
      {TimeCore: "WalkTime", OutCoreSuffix: "walk", DescSuffix: "walking"},
      {TimeCore: "TransitTime", OutCoreSuffix: "transit", DescSuffix: "transit"},
      {TimeCore: "NonAutoTime", OutCoreSuffix: "nonauto", DescSuffix: "transit or walking"}
    }
    for data in a_data do
      time_core = data.TimeCore
      out_core_suffix = data.OutCoreSuffix
      desc_suffix = data.DescSuffix

      out_core = name + "_Jobs_" + out_core_suffix
      mtx.AddCores({out_core})
      mtx.(out_core) := if mtx.(time_core) <= time_budget and mtx.(time_core) <> null then mtx.Employment //* mtx.(weight_field)
      mtx.(out_core) := if mtx.(out_core) = 0 then null else mtx.(out_core)
      v_jobs = mtx.GetVector({Core: out_core, Marginal: "Row Sum"})
      v_jobs.rowbased = "true"
      se.AddField({FieldName: out_core, Description: "Jobs within " + String(time_budget) + " minutes via " + desc_suffix})
		  se.(out_core) = if se.(name + "_dc") = 0 then null else v_jobs
    end
	end

  // Calculate per-capita stats
  per_capita_file = summary_dir + "/AM_per_capita_metrics.csv"
  file = OpenFile(per_capita_file, "w")
  WriteLine(file, "DC,Population,HoT,HoT_per_capita,Delay,Delay_per_capita")
  v_pop = se.HH_POP
  stats = MatrixStatistics(mtx.GetMatrixHandle(), )
  for i = 1 to weight_fields.length do
    weight_field = weight_fields[i]
    name = names[i]
    
    // Calculate disadvantaced population
    v_weight = se.(weight_field)
    v_dc_pop = v_pop * v_weight / 100
    tot_dc_pop = v_dc_pop.sum()

    // HoT
    total_hot = stats.(name + "_All_HoT").Sum
    hot_per_capita = total_hot / tot_dc_pop

    // Delay
    total_delay = stats.(name + "_All_Delay").Sum
    delay_per_capita = total_delay / tot_dc_pop

    WriteLine(
      file, name + "," + String(tot_dc_pop) + "," + String(total_hot) + "," + String(hot_per_capita) + "," +
      String(total_delay) + "," + String(delay_per_capita)
    )
  end
  CloseFile(file)
endmacro

/*

*/

Macro "Disadvantage Community Mapping" (Args)

	summary_dir = Args.[Output Folder] + "/_summaries/equity"
	se_file = Args.SE
	taz_file = Args.TAZs

	map_dir = summary_dir + "/maps"
	if GetDirectoryInfo(map_dir, "All") = null then CreateDirectory(map_dir)
	map = CreateObject("Map", taz_file)
	tazs = CreateObject("Table", map.GetActiveLayer())
	se = CreateObject("Table", se_file)
	join = tazs.Join({
		Table: se,
		LeftFields: "ID",
		RightFields: "TAZ"
	})

  // Used fixed scales for the maps depending on mode
  breaks = {
    auto: {
      {0, "true", 140000, "false"},
			{140000, "true", 330000, "false"},
			{330000, "true", 460000, "false"},
			{460000, "true", 570000, "false"},
			{570000, "true", 700000, "false"},
			{700000, "true", 800000, "false"},
			{800000, "true", 900000, "false"},
			{900000, "true", 2000000, "false"}
    },
    transit: {
      {0, "true", 3000, "false"},
			{3000, "true", 10000, "false"},
			{10000, "true", 17000, "false"},
			{17000, "true", 25000, "false"},
			{25000, "true", 34000, "false"},
			{34000, "true", 43000, "false"},
			{43000, "true", 54000, "false"},
			{54000, "true", 2000000, "false"}
    },
    walk: {
      {0, "true", 2000, "false"},
			{2000, "true", 5000, "false"},
			{5000, "true", 10000, "false"},
			{10000, "true", 18000, "false"},
			{18000, "true", 25000, "false"},
			{25000, "true", 34000, "false"},
			{34000, "true", 44000, "false"},
			{44000, "true", 2000000, "false"}
    }
  }

	a_dc = {"ZeroCar", "VehInsuff", "Senior", "Poverty"}
	suffixes = {"auto", "walk", "transit", "nonauto"}
	for dc in a_dc do
		for suffix in suffixes do
			field = dc + "_Jobs_" + suffix
      values = if suffix = "nonauto" then breaks.transit else breaks.(suffix)
			
			themename = "Jobs within 30 mins (" + suffix + ")"
			map.ColorTheme({
				ThemeName: themename,
				FieldName: field,
        Method: "manual",
        NumClasses: ArrayLength(values),
        Options: {Values: values},
				Colors: {
					StartColor: ColorRGB(65535, 65535, 54248),
					EndColor: ColorRGB(8738, 24158, 43176)
				}
			})
			map.CreateLegend({
				Title: "Disadvantage Community (" + dc + ")",
				DisplayLayers: "false" 
			})
			out_file = map_dir + "/" + field + ".map"
			map.Save(out_file)
			// TODO: can remove this after updating TC build (map class improvement)
			DestroyTheme(themename)
		end
	end
endmacro

/*

*/

Macro "Disadvantage Community Mode Shares" (Args)

	se_file = Args.SE
	trip_dir = Args.[Output Folder] + "/resident/trip_matrices"

	se = CreateObject("Table", se_file)

	types = {"ZeroCar", "VehInsuff", "Senior", "Poverty"}
	mtx_files = RunMacro("Catalog Files", {dir: trip_dir, ext: "mtx"})

	for type in types do
		// Add sub area index to the matrices
		for mtx_file in mtx_files do
			mtx = CreateObject("Matrix", mtx_file)
			mtx.AddIndex({
				IndexName: type,
				ViewName: se.GetView(),
				Filter: type + "_dc = 1",
				OriginalID: "TAZ",
				NewID: "TAZ",
				Dimension: "Both"
			})
		end

		// Call G2 summary macro
		Args.RowIndex = type
		Args.OutDir = Args.[Scenario Folder] + "/output/_summaries/equity/mode_shares"
		RunMacro("Summarize HB DC and MC", Args)
	end
endmacro

/*
Same basic macro as "Summarize NM", but with extra processing to filter by COC TAZs
*/

Macro "Summarize NM Disadvantage Community" (Args)
  
  out_dir = Args.[Output Folder]
  se_file = Args.SE
  
  per_dir = out_dir + "/resident/population_synthesis"
  per_file = per_dir + "/Synthesized_Persons.bin"
  per = CreateObject("Table", per_file)
  per_vw = per.GetView()
  nm_dir = out_dir + "/resident/nonmotorized"
  nm_file = nm_dir + "/_agg_nm_trips_daily.bin"
  nm = CreateObject("Table", nm_file)
  nm_vw = nm.GetView()
  se = CreateObject("Table", se_file)

  // join the se to both per/nm tables to ID CoC communities
  per_join = per.Join({
	Table: se,
	LeftFields: "HHTAZ",
	RightFields: "TAZ"
  })
  nm_join = nm.Join({
	Table: se,
	LeftFields: "TAZ",
	RightFields: "TAZ"
  })

  trip_types = RunMacro("Get HB Trip Types", Args)
  dc_types = {"ZeroCar", "Senior", "Poverty"}

  for dc in dc_types do
	dc_field_name = dc + "_dc"

	summary_file = out_dir + "/_summaries/equity/mode_shares/hb_nm_summary_" + dc + ".csv"
	f = OpenFile(summary_file, "w")
	WriteLine(f, "trip_type,moto_total,moto_share,nm_total,nm_share")

	// create selection sets of just CoC people/tazs
	per_join.SelectByQuery({
		SetName: "dc",
		Query: dc_field_name + " = 1"
	})
	nm_join.SelectByQuery({
		SetName: "dc",
		Query: dc_field_name + " = 1"
	})

	for trip_type in trip_types do
		// moto_v = GetDataVector(per_vw + "|", trip_type, )
		moto_v = per_join.(trip_type)
		moto_total = VectorStatistic(moto_v, "Sum", )
		if trip_type = "W_HB_EK12_All" then do
			moto_share = 100
			nm_total = 0
			nm_share = 0
		end else do
			// nm_v = GetDataVector(nm_vw + "|", trip_type, )
			nm_v = nm_join.(trip_type)
			nm_total = VectorStatistic(nm_v, "Sum", )
			moto_share = round(moto_total / (moto_total + nm_total) * 100, 2)
			nm_share = round(nm_total / (moto_total + nm_total) * 100, 2)
		end

		WriteLine(f, trip_type + "," + String(moto_total) + "," + String(moto_share) + "," + String(nm_total) + "," + String(nm_share))
	end
  end

  CloseFile(f)
endmacro

/*

*/

Macro "Summarize HH Strata" (Args)

  scen_dir = Args.[Scenario Folder]
  summary_dir = scen_dir + "/output/_summaries"
  hh_file = Args.Households
  subarea = Args.subarea
  taz_file = Args.TAZs

  tbl = CreateObject("Table", hh_file)

  // if doing a subarea filter the table
  if subarea then do
    tbl.AddField("subarea")
    taz = CreateObject("Table", taz_file)
    join = tbl.Join({
      Table: taz,
      LeftFields: "ZoneID",
      RightFields: "ID"
    })
    join.subarea = join.in_subarea
    join = null
    tbl.SelectByQuery({
      SetName: "subarea",
      Query: "subarea = 1"
    })
    tbl = tbl.Export()
  end

  // aggregate/summarize table
  agg = tbl.Aggregate({
    GroupBy: "market_segment",
    FieldStats: {market_segment: "count"}
  })
  agg.RenameField({FieldName: "count_market_segment", NewName: "count"})

  if subarea
    then out_file = summary_dir + "/hhstrata_subarea.csv"
    else out_file = summary_dir + "/hhstrata.csv"
  agg.Export({FileName: out_file})
endmacro

Macro "Aggregate Transit Flow by Route" (Args)
  scen_dir = Args.[Scenario Folder]
  out_dir  = Args.[Output Folder]
  assn_dir = out_dir + "/assignment/transit"
  output_dir = out_dir + "/assignment/transit/aggregate"
  if GetDirectoryInfo(output_dir, "All") = null then CreateDirectory(output_dir)
  access_modes = Args.access_modes
  mode_table = Args.TransModeTable
  periods = Args.periods
  orig_transit_modes = RunMacro("Get Transit Modes", mode_table)

  // Loop through transit assn bin files
  // By daily
  for access_mode in access_modes do
    if access_mode = "w" then transit_modes = orig_transit_modes + {"all"}
    else transit_modes = orig_transit_modes 

    for transit_mode in transit_modes do
      for period in periods do 
        filename = assn_dir + "/" + period + "_" + access_mode + "_" + transit_mode + ".bin"
        df = CreateObject("df", filename)
        df.select({"Route", "From_MP", "To_MP", "From_Stop", "To_Stop", "TransitFlow"})
        if daily = null then daily = df.copy()
        else do
          df.select({"Route", "From_Stop", "To_Stop", "TransitFlow"}) 
          daily.left_join(df, {"Route", "From_Stop", "To_Stop"}, {"Route", "From_Stop", "To_Stop"})
          daily.tbl.("TransitFlow_x") = nz(daily.tbl.("TransitFlow_x")) + nz(daily.tbl.("TransitFlow_y"))
          daily.rename("TransitFlow_x", "TransitFlow")
          daily.remove("TransitFlow_y")
          end
      end
      daily.write_bin(output_dir + "/daily_"+ access_mode + "_" + transit_mode + ".bin")
      daily = null
    end
  end

  // By daily and access mode
  for transit_mode in transit_modes do
    if access_mode = "w" then transit_modes = orig_transit_modes + {"all"}
    else transit_modes = orig_transit_modes

    for period in periods do
      for access_mode in access_modes do 
        filename = assn_dir + "/" + period + "_" + access_mode + "_" + transit_mode + ".bin"
        df = CreateObject("df", filename)
        df.select({"Route", "From_MP", "To_MP", "From_Stop", "To_Stop", "TransitFlow"})
        if daily = null then daily = df.copy()
        else do 
          df.select({"Route", "From_Stop", "To_Stop", "TransitFlow"})
          daily.left_join(df, {"Route", "From_Stop", "To_Stop"}, {"Route", "From_Stop", "To_Stop"})
          daily.tbl.("TransitFlow_x") = nz(daily.tbl.("TransitFlow_x")) + nz(daily.tbl.("TransitFlow_y"))
          daily.rename("TransitFlow_x", "TransitFlow")
          daily.remove("TransitFlow_y")
          end
      end
    end
    daily.write_bin(output_dir + "/daily_" + transit_mode + ".bin")
    daily = null
  end

  // By daily and transit mode
  for access_mode in access_modes do 
    if access_mode = "w" then transit_modes = orig_transit_modes + {"all"}
    else transit_modes = orig_transit_modes
    
    for transit_mode in transit_modes do
      for period in periods do
        
          filename = assn_dir + "/" + period + "_" + access_mode + "_" + transit_mode + ".bin"
          df = CreateObject("df", filename)
          df.select({"Route", "From_MP", "To_MP", "From_Stop", "To_Stop", "TransitFlow"})
          if daily = null then daily = df.copy()
          else do 
            df.select({"Route", "From_Stop", "To_Stop", "TransitFlow"})
            daily.left_join(df, {"Route", "From_Stop", "To_Stop"}, {"Route", "From_Stop", "To_Stop"})
            daily.tbl.("TransitFlow_x") = nz(daily.tbl.("TransitFlow_x")) + nz(daily.tbl.("TransitFlow_y"))
            daily.rename("TransitFlow_x", "TransitFlow")
            daily.remove("TransitFlow_y")
            end
        end
      end
      daily.write_bin(output_dir + "/daily_" + access_mode + ".bin")
      daily = null
  end

endmacro

Macro "Validation Reports" (Args)
  root_dir = Args.[Base Folder]
  scen_dir = Args.[Scenario Folder]
  skim_dir = Args.[Output Folder] + "\\skims\\roadway"
  obs_dir = root_dir + "/other/_reportingtool/validation_obs_data"
  summary_dir = scen_dir + "/output/_summaries"
  validation_dir = summary_dir + "/validation"
  if GetDirectoryInfo(validation_dir, "All") = null then CreateDirectory(validation_dir)

  // 1. NM trips
  obs_data = obs_dir + "/nm_calibration_targets.csv"
  est_data = summary_dir + "/resident_hb/hb_nm_summary.csv"
  
  est_tbl = CreateObject("Table", est_data)
  obs_tbl = CreateObject("Table", obs_data)

	join = obs_tbl.Join({
		Table: est_tbl,
		LeftFields: "trip_type",
		RightFields: "trip_type"
	})
  join.Export({FileName: validation_dir + "/nonmotorized.bin"})

  join = CreateObject("Table", validation_dir + "/nonmotorized.bin")
  join.AddField({FieldName: "est_nm_share", Type: "string"})
  join.AddField({FieldName: "pcfdiff_nm_share", Type: "string"})
  v1 = join.nm_share/100
  v2 = (v1 - join.obs_nm_share)/join.obs_nm_share
  join.est_nm_share = Format(v1, "*.000")
  join.pcfdiff_nm_share = Format(v2, "*.00")
  join.DropFields({FieldNames:{"trip_type:1", "moto_total", "moto_share", "nm_total", "nm_share"}})

  join.Export({FileName: validation_dir + "/nonmotorized.csv"})
  join = null

  DeleteFile(validation_dir + "/nonmotorized.bin")
  DeleteFile(validation_dir + "/nonmotorized.dcb")

  // 2. Auto ownership
  obs_data = obs_dir + "/ao_calib_targets.csv"
  est_data = scen_dir + "/output/resident/population_synthesis/Synthesized_HHs.bin"

  est_tbl = CreateObject("Table", est_data)
  agg_est_tbl = est_tbl.Aggregate({
    GroupBy: "Autos",
    FieldStats: {WEIGHT: "sum"}
  })
	sum_est_weight = VectorStatistic(agg_est_tbl.sum_WEIGHT, "Sum", )
  v_est_share = agg_est_tbl.sum_WEIGHT / sum_est_weight
  agg_est_tbl.AddField({FieldName: "est_weight", Type: "string"})
  agg_est_tbl.AddField({FieldName: "est_share_temp", Type: "real"})
  agg_est_tbl.AddField({FieldName: "est_share", Type: "string"})
  agg_est_tbl.AddField({FieldName: "pcfdiff_share", Type: "string"})
  agg_est_tbl.est_weight = Format(agg_est_tbl.sum_WEIGHT, ",*0.")
  agg_est_tbl.est_share_temp = v_est_share
  
  obs_tbl = CreateObject("Table", obs_data)
  
  join = obs_tbl.Join({
		Table: agg_est_tbl,
		LeftFields: "autos",
		RightFields: "Autos"
	})
  join.Export({FileName: validation_dir + "/ao.bin"})

  join = CreateObject("Table", validation_dir + "/ao.bin")
	v = (join.est_share_temp - join.obs_share)/join.obs_share
  join.pcfdiff_share = Format(v, "*.00")
  join.est_share = Format(join.est_share_temp, ",*.00")
  join.DropFields({FieldNames:{"sum_WEIGHT", "est_share_temp"}})
  join.Export({FileName: validation_dir + "/ao_ownership.csv"})
  join = null

  DeleteFile(validation_dir + "/ao.bin")
  DeleteFile(validation_dir + "/ao.dcb")

  //3. Destination Choice
  obs_data = obs_dir + "/hb_trip_stats_by_type_obs.csv"
  est_data = summary_dir + "/resident_hb/hb_trip_stats_by_type.csv"

  obs_tbl = CreateObject("Table", obs_data)
  est_tbl = CreateObject("Table", est_data)

  join = obs_tbl.Join({
      Table: est_tbl,
      LeftFields: "matrix",
      RightFields: "matrix"
    })
  join.Export({FileName: validation_dir + "/destinationchoice.bin"})

  join = CreateObject("Table", validation_dir + "/destinationchoice.bin")
  join.AddField({FieldName: "est_avg_length_mi", Type: "string"})
  join.est_avg_length_mi = Format(join.avg_length_mi, "*.00")
  join.AddField({FieldName: "pcfdiff_length_mi", Type: "string"})
  v = (join.avg_length_mi - join.obs_avg_length_mi)/join.obs_avg_length_mi
  join.pcfdiff_length_mi = Format(v, "*.00")
  join.DropFields({FieldNames: {"core",	"Sum",	"SumDiag",	"PctDiag", "avg_length_mi", "avg_time_min", "matrix:1",	"core:1",	"Sum:1",	"SumDiag:1",	"PctDiag:1", "avg_time_min:1"}})
  join.Export({FileName: validation_dir + "/destinationchoice.csv"})
  join = null

  DeleteFile(validation_dir + "/destinationchoice.bin")
  DeleteFile(validation_dir + "/destinationchoice.dcb")

  //4. Mode Choice
  obs_data = root_dir + "/other/_reportingtool/validation_obs_data/Target_HB_MCShares_agg.csv"
  est_data = summary_dir + "/resident_hb/hb_trip_mode_shares.csv"

  obs_tbl = CreateObject("Table", obs_data)

  est_tbl = CreateObject("Table", est_data)

  join = obs_tbl.Join({
      Table: est_tbl,
      LeftFields: {"trip_type", "mode"},
      RightFields: {"trip_type", "mode"}
    })
  join.Export({FileName: validation_dir + "/modechoice.bin"})

  join = CreateObject("Table", validation_dir + "/modechoice.bin")
  join.AddField({FieldName: "est_share", Type: "real"})
  join.est_share = join.pct/100
  join.AddField({FieldName: "pcfdiff_share", Type: "string"})
  v = (join.est_share - join.obs_share)/join.obs_share
  join.pcfdiff_share = Format(v, "*.00")
  join.DropFields({FieldNames: {"trip_type:1",	"mode:1",	"Sum",	"total", "pct"}})
  join.Export({FileName: validation_dir + "/modechoice.csv"})
  join = null

  DeleteFile(validation_dir + "/modechoice.bin")
  DeleteFile(validation_dir + "/modechoice.dcb")

  //5. Transit assignment
  obs_data = root_dir + "/other/_reportingtool/validation_obs_data/transit_ridership.csv"
  est_data = summary_dir + "/transit/boardings_and_alightings_daily_by_agency.csv"

  obs_tbl = CreateObject("Table", obs_data)  
  est_tbl = CreateObject("Table", est_data)

  join = obs_tbl.Join({
      Table: est_tbl,
      LeftFields: "Agency",
      RightFields: "agency"
    })
  join.Export({FileName: validation_dir + "/transitassignment.bin"})

  join = CreateObject("Table", validation_dir + "/transitassignment.bin")
  join.RenameField({FieldName: "obs_ridership", NewName: "obs_ridership_temp"})
  join.RenameField({FieldName: "On", NewName: "est_ridership_temp"})
  join.AddField({FieldName: "obs_ridership", Type: "string"})
  join.obs_ridership = Format(join.obs_ridership_temp, "*,.")
  join.AddField({FieldName: "est_ridership", Type: "string"})
  join.est_ridership = Format(join.est_ridership_temp, "*,.")
  join.AddField({FieldName: "pcfdiff_ridership", Type: "string"})
  v = (join.est_ridership_temp - join.obs_ridership_temp)/join.obs_ridership_temp
  join.pcfdiff_ridership = Format(v, "*.00")
  join.DropFields({FieldNames: {"obs_ridership_temp", "agency:1", "est_ridership_temp","Off",	"DriveAccessOn",	"WalkAccessOn",	"DirectTransferOn",	"WalkTransferOn",	"DirectTransferOff",	"WalkTransferOff",	"EgressOff"}})
  join.Export({FileName: validation_dir + "/transitassignment.csv"})
  join = null

  DeleteFile(validation_dir + "/transitassignment.bin")
  DeleteFile(validation_dir + "/transitassignment.dcb")

  //6. R-square for Regionwide Estimated Volumes vs. Traffic Counts

  //7. Concatenate reports
  opts = null
  opts.model_dir = Args.[Base Folder]
  opts.scen_dir = Args.[Scenario Folder]
  opts.inputtable_file = opts.model_dir + "\\other\\_reportingtool\\validation_tablenames.csv"
  opts.output_file = opts.scen_dir + "\\output\\_summaries\\validation\\validation_summary.csv"
  RunMacro("Concatenate Files", opts)
  
endmacro

/*

*/

Macro "Export Highway Geodatabase" (Args)
  
  hwy_dbd = Args.Links

  {drive, folder, name, ext} = SplitPath(hwy_dbd)
  out_file = drive + folder + "scenario_links.gdb"
  // TC is unable to delete the existing GDB, so we need to delete it manually
  // if you want to recreate it.
  if GetFileInfo(out_file) <> null then return()
  
  // Create a map and export the link layer
  map = CreateObject("Map", hwy_dbd)
  {nlyr, llyr} = map.GetLayerNames()
  
  SetLayer(llyr)
  cur = CreateObject("Utils.Currency")

  opts = null
  opts.[Layer Name] = llyr
  {f,fx} = GetFields(llyr, "All")
  opts.Fields = {
      llyr + ".ID",
      llyr + ".Dir",
      llyr + ".Length",
      llyr + ".RoadName",
      llyr + ".AltName",
      llyr + ".NCDOTClass",
      llyr + ".HCMType",
      llyr + ".ABLanes",
      llyr + ".BALanes",
      llyr + ".PostedSpeed",
      llyr + ".HCMMedian",
      llyr + ".DTWB",
      llyr + ".HOV",
      llyr + ".BOSSS",
      llyr + ".TollType",
      llyr + ".TollCostT",
      llyr + ".TollCostNT",
      llyr + ".FFSpeed",
      llyr + ".FFTime",
      llyr + ".ABAMTime",
      llyr + ".BAAMTime",
      llyr + ".ABMDTime",
      llyr + ".BAMDTime",
      llyr + ".ABPMTime",
      llyr + ".BAPMTime",
      llyr + ".ABNTTime",
      llyr + ".BANTTime",
      llyr + ".Max_Time_AM",
      llyr + ".Max_VOC_AM",
      llyr + ".Tot_VMT_AM",
      llyr + ".Tot_VHT_AM",
      llyr + ".AB_Speed_AM",
      llyr + ".BA_Speed_AM",
      llyr + ".AB_Flow_AM",
      llyr + ".BA_Flow_AM",
      llyr + ".Tot_Flow_AM",
      llyr + ".Max_Time_MD",
      llyr + ".Max_VOC_MD",
      llyr + ".Tot_VMT_MD",
      llyr + ".Tot_VHT_MD",
      llyr + ".AB_Speed_MD",
      llyr + ".BA_Speed_MD",
      llyr + ".AB_Flow_MD",
      llyr + ".BA_Flow_MD",
      llyr + ".Tot_Flow_MD",
      llyr + ".Max_Time_PM",
      llyr + ".Max_VOC_PM",
      llyr + ".Tot_VMT_PM",
      llyr + ".Tot_VHT_PM",
      llyr + ".AB_Speed_PM",
      llyr + ".BA_Speed_PM",
      llyr + ".AB_Flow_PM",
      llyr + ".BA_Flow_PM",
      llyr + ".Tot_Flow_PM",
      llyr + ".Max_Time_NT",
      llyr + ".Max_VOC_NT",
      llyr + ".Tot_VMT_NT",
      llyr + ".Tot_VHT_NT",
      llyr + ".AB_Speed_NT",
      llyr + ".BA_Speed_NT",
      llyr + ".AB_Flow_NT",
      llyr + ".BA_Flow_NT",
      llyr + ".Tot_Flow_NT",
      llyr + ".AB_Flow_Daily",
      llyr + ".BA_Flow_Daily",
      llyr + ".Total_Flow_Daily",
      llyr + ".Total_CV_Flow_Daily",
      llyr + ".Total_SUT_Flow_Daily",
      llyr + ".Total_MUT_Flow_Daily",
      llyr + ".Total_VMT_Daily",
      llyr + ".Total_VHT_Daily",
      llyr + ".Total_Delay_Daily",
      llyr + ".Tot_Delay_AM",
      llyr + ".Tot_Delay_MD",
      llyr + ".Tot_Delay_PM",
      llyr + ".Tot_Delay_NT"
    }
  opts.ID = fx[1]
  opts.[EPSG Datum] = 4269 // North America
  ExportGdalVector(llyr + "|", out_file, "FileGDB", opts)
endmacro

/*

*/

Macro "Performance Measures Reports" (Args)
  //Set input file path
  root_dir = Args.[Base Folder]
  scen_dir = Args.[Scenario Folder]
  taz_file = Args.TAZs
  periods = Args.periods
  out_dir = scen_dir + "/output"
  summary_dir = scen_dir + "/output/_summaries"
  pm_dir = summary_dir + "/performance_measures"
  if GetDirectoryInfo(pm_dir, "All") = null then CreateDirectory(pm_dir)
	hwy_dbd = Args.Links
  mode_table = Args.TransModeTable
  access_modes = Args.access_modes
  group_fields = {"Region", "MPO", "County"}

	//1. Highway performance measures
  //Read highway link layer
  {nLayer, llyr} = GetDBLayers(hwy_dbd)
	llyr = AddLayerToWorkspace(llyr, hwy_dbd, llyr)
  hwy_tbl = CreateObject("Table", llyr)
  hwy_tbl.SelectByQuery({
    SetName: "to_export",
    Query: "HCMType <> 'CC'"
  })
  tbl = hwy_tbl.Export()

  //1.1 Daily VMT 1.2 Daily VHT
  out_tbl = CreateObject("Table", {Fields: {
      {FieldName: "VMT_and_VHT", Type: "String"},
      {FieldName: "Region", Type: "real"}
    }})
  out_tbl.AddRows({EmptyRows: 2})
  out_tbl.VMT_and_VHT = {"Total VMT (no CC)", "Total VHT (no CC)"}

  Total_VMT_Daily = tbl.Total_VMT_Daily.sum()
  Total_VHT_Daily = tbl.Total_VHT_Daily.sum()
  Total_VMT_AM = tbl.Tot_VMT_AM.sum()
  Total_VHT_AM = tbl.Tot_VHT_AM.sum()
  Total_VMT_PM = tbl.Tot_VMT_PM.sum()
  Total_VHT_PM = tbl.Tot_VHT_PM.sum()
  a_region = {Total_VMT_Daily, Total_VHT_Daily}  
  out_tbl.Region = A2V(a_region)
  out_tbl.Export({FileName: pm_dir + "/VMTVHT.csv"})

  fields_to_sum = {Total_VMT_Daily: "sum", Total_VHT_Daily:"sum"}
  for group_field in group_fields do 
    if group_field = "Region" then continue
    out_file = pm_dir + "/VMTVHT_by" + group_field + ".csv"
    agg = tbl.Aggregate({
      GroupBy: group_field,
      FieldStats: fields_to_sum
    })
    agg.Export({FileName: out_file})
  end

  //1.3 1.4 Daily and peak average speed by facility
  // Calculate all facility region
  out_tbl = CreateObject("Table", {Fields: {
      {FieldName: "AvgSpeedDaily", Type: "String"},
      {FieldName: "Region", Type: "real"}
    }})
  out_tbl.AddRows({EmptyRows: 1})
  out_tbl.AvgSpeedDaily = {"AllFacility"}
  out_tbl.Region = Total_VMT_Daily/Total_VHT_Daily
  out_tbl.Export({FileName: pm_dir + "/AvgSpeed_byregion_daily.csv"})

  out_tbl = CreateObject("Table", {Fields: {
      {FieldName: "AvgSpeedAM", Type: "String"},
      {FieldName: "Region", Type: "real"}
    }})
  out_tbl.AddRows({EmptyRows: 1})
  out_tbl.AvgSpeedAM = {"AllFacility"}
  out_tbl.Region = Total_VMT_AM/Total_VHT_AM
  out_tbl.Export({FileName: pm_dir + "/AvgSpeed_byregion_AM.csv"})

  out_tbl = CreateObject("Table", {Fields: {
      {FieldName: "AvgSpeedPM", Type: "String"},
      {FieldName: "Region", Type: "real"}
    }})
  out_tbl.AddRows({EmptyRows: 1})
  out_tbl.AvgSpeedPM = {"AllFacility"}
  out_tbl.Region = Total_VMT_PM/Total_VHT_PM
  out_tbl.Export({FileName: pm_dir + "/AvgSpeed_byregion_PM.csv"})
  
  // Calculate by facility by MPO/County
  fields_to_sum = {Total_VMT_Daily: "sum", Total_VHT_Daily:"sum", Tot_VMT_AM: "sum", Tot_VHT_AM: "sum", Tot_VMT_PM: "sum", Tot_VHT_PM: "sum"}
  outfields = {
    {FieldName: "AvgSpeed_Daily", Type: "real"},
    {FieldName: "AvgSpeed_AM", Type: "real"},
    {FieldName: "AvgSpeed_PM", Type: "real"}
  }

  for group_field in group_fields do 
    out_file = pm_dir + "/AvgSpeed_byfacility_by" + group_field + ".csv"
    if group_field = "Region" then group_field = "HCMType" else group_field = {group_field} + {"HCMType"}
    agg = tbl.Aggregate({
      GroupBy: group_field,
      FieldStats: fields_to_sum
    })
    agg.AddFields({Fields: outfields})
    agg.AvgSpeed_Daily = agg.sum_Total_VMT_Daily/agg.sum_Total_VHT_Daily
    agg.AvgSpeed_AM = agg.sum_Tot_VMT_AM/agg.sum_Tot_VHT_AM
    agg.AvgSpeed_PM = agg.sum_Tot_VMT_PM/agg.sum_Tot_VHT_PM
    agg.DropFields({FieldNames:{"sum_Total_VMT_Daily", "sum_Total_VHT_Daily", "sum_Tot_VMT_AM", "sum_Tot_VHT_AM", "sum_Tot_VMT_PM", "sum_Tot_VHT_PM"}})
    agg.Export({FileName: out_file})
  end
  
  // Calculate all facility by MPO/County
  for group_field in group_fields do 
    out_file = pm_dir + "/AvgSpeed_by" + group_field + ".csv"
    if group_field = "Region" then continue
    agg = tbl.Aggregate({
      GroupBy: group_field,
      FieldStats: fields_to_sum
    })
    agg.AddFields({Fields: outfields})
    agg.AvgSpeed_Daily = agg.sum_Total_VMT_Daily/agg.sum_Total_VHT_Daily
    agg.AvgSpeed_AM = agg.sum_Tot_VMT_AM/agg.sum_Tot_VHT_AM
    agg.AvgSpeed_PM = agg.sum_Tot_VMT_PM/agg.sum_Tot_VHT_PM
    agg.DropFields({FieldNames:{"sum_Total_VMT_Daily", "sum_Total_VHT_Daily", "sum_Tot_VMT_AM", "sum_Tot_VHT_AM", "sum_Tot_VMT_PM", "sum_Tot_VHT_PM"}})
    agg.Export({FileName: out_file})
  end

  /*
  //1.5 Daily Average Travel Length - All HB Trips
  daily_mtx_file = summary_dir + "/resident_hb/AllHBTrips.mtx"
  hbw_mtx_file = summary_dir + "/resident_hb/W_HB_W_All.mtx"

  skim_mtx_file = skim_dir + "/skim_hov_AM.mtx"
  skim_mtx = CreateObject("Matrix", skim_mtx_file)
  skim_coreD = skim_mtx.GetCore("Length (Skim)")
  skim_coreT = skim_mtx.GetCore("CongTime")
  
  for mtx_file in total_files do
    mtx = CreateObject("Matrix", mtx_file)
    trip_core = mtx.GetCore("total")

    out_mtx_file = Substitute(mtx_file, ".mtx", "_tlfd.mtx", )
    tld = CreateObject("Distribution.TLD")
    tld.StartValue = 0
    tld.BinSize = 1
    tld.TripMatrix = trip_core
    tld.ImpedanceMatrix = skim_coreD
    tld.OutputMatrix(out_mtx_file)
    tld.Run()
    res = tld.GetResults()
    avg_length = res.Data.AvTripLength
    trip_lengths = trip_lengths + {avg_length}

    out_mtx_file = Substitute(mtx_file, ".mtx", "_tlft.mtx", )
    tld = CreateObject("Distribution.TLD")
    tld.StartValue = 0
    tld.BinSize = 1
    tld.TripMatrix = trip_core
    tld.ImpedanceMatrix = skim_coreT
    tld.OutputMatrix(out_mtx_file)
    tld.Run()
    res = tld.GetResults()
    avg_time = res.Data.AvTripLength
    trip_times = trip_times + {avg_time}
  end
  mtx = null
  trip_core = null
  */

  //1.10 Hours of delay
  out_tbl = CreateObject("Table", {Fields: {
      {FieldName: "Delay", Type: "String"},
      {FieldName: "Region", Type: "real"}
    }})
  out_tbl.AddRows({EmptyRows: 2})
  out_tbl.Delay = {"Total hours of delay", "Truck hours of delay"}

  delayvmt_table = summary_dir + "/VMT_Delay/link_VMT_Delay.csv"
  tbl2 = CreateObject("Table", delayvmt_table)
  region_delay = tbl2.Total_Delay_Daily.sum()
  region_truckdelay = tbl2.Delay_SUT_Daily.sum() + tbl2.Delay_MUT_Daily.sum()
  a_region = {region_delay, region_truckdelay}
  out_tbl.Region = A2V(a_region)
  out_tbl.Export({FileName: pm_dir + "/delay.csv"})
  
  for group_field in group_fields do 
    if group_field = "Region" then continue
    agg = tbl2.Aggregate({
      GroupBy: group_field,
      FieldStats: {
        Total_Delay_Daily: "sum",
        Delay_SUT_Daily: "sum",
        Delay_MUT_Daily: "sum"
      }
    })
    agg.AddField("Total_Truck_Delay_Daily")
    agg.Total_Truck_Delay_Daily = agg.sum_Delay_SUT_Daily + agg.sum_Delay_MUT_Daily
    out_file = pm_dir + "/Delay_by_" + group_field + ".csv"
    agg.Export({FileName: out_file})  
  end

  //1.11 1.12 Percent of VMT experiencing congestion - All Day and Peak
  tbl.AddField("CongestedVMT_Daily")
  tbl.CongestedVMT_Daily = tbl.CongestedVMT_AM + tbl.CongestedVMT_MD + tbl.CongestedVMT_PM + tbl.CongestedVMT_NT

  // Calculate all facility region
  out_tbl = CreateObject("Table", {Fields: {
      {FieldName: "PctCongestionDaily", Type: "String"},
      {FieldName: "Region", Type: "real"}
    }})
  out_tbl.AddRows({EmptyRows: 1})
  out_tbl.PctCongestionDaily = {"AllFacility"}
  out_tbl.Region = tbl.CongestedVMT_Daily.sum()/tbl.Total_VMT_Daily.sum()
  out_tbl.Export({FileName: pm_dir + "/PctCongestion_byregion_daily.csv"})

  out_tbl = CreateObject("Table", {Fields: {
      {FieldName: "PctCongestionAM", Type: "String"},
      {FieldName: "Region", Type: "real"}
    }})
  out_tbl.AddRows({EmptyRows: 1})
  out_tbl.PctCongestionAM = {"AllFacility"}
  out_tbl.Region = tbl.CongestedVMT_AM.sum()/tbl.Tot_VMT_AM.sum()
  out_tbl.Export({FileName: pm_dir + "/PctCongestion_byregion_AM.csv"})

  out_tbl = CreateObject("Table", {Fields: {
      {FieldName: "PctCongestionPM", Type: "String"},
      {FieldName: "Region", Type: "real"}
    }})
  out_tbl.AddRows({EmptyRows: 1})
  out_tbl.PctCongestionPM = {"AllFacility"}
  out_tbl.Region = tbl.CongestedVMT_PM.sum()/tbl.Tot_VMT_PM.sum()
  out_tbl.Export({FileName: pm_dir + "/PctCongestion_byregion_PM.csv"})

  // Define field specs
  fields_to_sum = {Total_VMT_Daily: "sum", CongestedVMT_Daily:"sum", Tot_VMT_AM: "sum", CongestedVMT_AM: "sum", Tot_VMT_PM: "sum", CongestedVMT_PM: "sum"}
  outfields = {
    {FieldName: "PctCongestion_Daily", Type: "real"},
    {FieldName: "PctCongestion_AM", Type: "real"},
    {FieldName: "PctCongestion_PM", Type: "real"}
  }
  
  // Calculate by facility by MPO/County
  for group_field in group_fields do 
    out_file = pm_dir + "/CgVMTpct_byfacility_by" + group_field + ".csv"
    if group_field = "Region" then group_field = "HCMType" else group_field = {group_field} + {"HCMType"}
    agg = tbl.Aggregate({
      GroupBy: group_field,
      FieldStats: fields_to_sum
    })
    agg.AddFields({Fields: outfields})
    agg.PctCongestion_Daily = agg.sum_CongestedVMT_Daily/agg.sum_Total_VMT_Daily
    agg.PctCongestion_AM = agg.sum_CongestedVMT_AM/agg.sum_Tot_VMT_AM
    agg.PctCongestion_PM = agg.sum_CongestedVMT_PM/agg.sum_Tot_VMT_PM
    agg.DropFields({FieldNames:{"sum_Total_VMT_Daily", "sum_CongestedVMT_Daily", "sum_Tot_VMT_AM", "sum_CongestedVMT_AM", "sum_Tot_VMT_PM", "sum_CongestedVMT_PM"}})
    agg.Export({FileName: out_file})
  end
  
  // Calculate all facility by MPO/County
  for group_field in group_fields do 
    out_file = pm_dir + "/CgVMTpct_by" + group_field + ".csv"
    if group_field = "Region" then continue
    agg = tbl.Aggregate({
      GroupBy: group_field,
      FieldStats: fields_to_sum
    })
    agg.AddFields({Fields: outfields})
    agg.PctCongestion_Daily = agg.sum_CongestedVMT_Daily/agg.sum_Total_VMT_Daily
    agg.PctCongestion_AM = agg.sum_CongestedVMT_AM/agg.sum_Tot_VMT_AM
    agg.PctCongestion_PM = agg.sum_CongestedVMT_PM/agg.sum_Tot_VMT_PM
    agg.DropFields({FieldNames:{"sum_Total_VMT_Daily", "sum_CongestedVMT_Daily", "sum_Tot_VMT_AM", "sum_CongestedVMT_AM", "sum_Tot_VMT_PM", "sum_CongestedVMT_PM"}})
    agg.Export({FileName: out_file})
  end

  

  //6. TAZ Measures
  // Build an equivalency array that maps modes to summary mode levels
    equiv = {
      sov: "sov",
      auto: "sov", //university auto mode is set to sov
      hov2: "hov",
      hov3: "hov",
      walk: "nm",
      bike: "nm",
      walkbike: "nm",
      auto_pay: "hov", //NHB auto pay mode is set to hov
      transit: "nhballtransit"
    }
    transit_modes = RunMacro("Get Transit Modes", mode_table)
    for access_mode in access_modes do
      for transit_mode in transit_modes do
        name = access_mode + "_" + transit_mode
        if transit_mode = "lb" or transit_mode = "eb" then
          equiv.(name) = "bus" else
          equiv.(name) = transit_mode
      end
    end
  
    // Get a vector of IDs from one of the matrices
    mtx_files = RunMacro("Catalog Files", {dir: out_dir + "/assignment/roadway", ext: "mtx"})
    mtx = CreateObject("Matrix", mtx_files[1])
    core_names = mtx.GetCoreNames()
    v_id = mtx.GetVector({Core: core_names[1], Index: "Row"})

    // create a table to store results
    tbl = CreateObject("Table", {Fields: {
      {FieldName: "TAZ", Type: "Integer"}
    }})
    tbl.AddRows({EmptyRows: v_id.length})
    tbl.TAZ = v_id

    // Loop through each group
    groups = {"Daily", "PM", "W_HB_W"}

    for group in groups do

      // Resident HB motorized trips
      trip_dir = out_dir + "/resident/trip_matrices"
      result = RunMacro("Summarize HB Univ RowSums", {equiv: equiv, group: group, trip_dir: trip_dir, result: result})

      // Resident HB nm trips
      trip_mtx = out_dir + "/resident/nonmotorized/nm_gravity.mtx"
      result = RunMacro("Summarize HB NM RowSums", {group: group, trip_mtx: trip_mtx, result: result})

      // University trips
      trip_dir = out_dir + "/university/mode"
      if group <> "W_HB_W" then result = RunMacro("Summarize HB Univ RowSums", {equiv: equiv, group: group, trip_dir: trip_dir, result: result})

      // NHB trips
      trip_bin = out_dir + "/resident/nhb/dc/NHBTripsForDC.bin"
      if group <> "W_HB_W" then result = RunMacro("Summarize NHB", {equiv: equiv, group: group, trip_bin: trip_bin, result: result})
      
    end
        
    // Save results to the output table and add county info from the TAZ layer
    for i = 1 to result.length do
      field_name = result[i][1]
      tbl.AddField(field_name)
      tbl.(field_name) = result.(field_name)
    end
    out_file = pm_dir + "/taz_measures.bin"
    tbl.Export({FileName: out_file})

endmacro

Macro "Summarize HB Univ RowSums" (MacroOpts)
  
  equiv = MacroOpts.equiv
  trip_dir = MacroOpts.trip_dir
  group = MacroOpts.group
  result = MacroOpts.result

  mtx_files = RunMacro("Catalog Files", {dir: trip_dir, ext: "mtx"})
  for mtx_file in mtx_files do
    if group = "PM" and position(mtx_file, group) = 0 then continue
    if group = "W_HB_W" and position(mtx_file, group) = 0 then continue

    mtx = CreateObject("Matrix", mtx_file)
    core_names = mtx.GetCoreNames()
    for core_name in core_names do
      // hb motorized and univ can be handled below, core names have mode info
      if equiv.(core_name) = null then continue
      out_name = equiv.(core_name) + "_" + group
      v = mtx.GetVector({Core: core_name, Marginal: "Row Sum"})

      if TypeOf(result.(out_name)) = "null"
        then result.(out_name) = nz(v)
        else result.(out_name) = result.(out_name) + nz(v)
    end
  end
  return(result)
endmacro

Macro "Summarize HB NM RowSums" (MacroOpts)
  
  // hb nm matrix needs special handling, core names do not have mode info
  trip_mtx = MacroOpts.trip_mtx
  group = MacroOpts.group
  result = MacroOpts.result

  mtx = CreateObject("Matrix", trip_mtx)
  core_names = mtx.GetCoreNames()
  for core_name in core_names do
    parts = ParseString(core_name, "_")
    if group = "Daily" and ArrayLength(parts) <> 4 then continue
    if group = "PM" and right(core_name, 2) <> "PM" then continue
    if group = "W_HB_W" and core_name <> "W_HB_W_All" then continue

    out_name = "nm_" + group
    v = mtx.GetVector({Core: core_name, Marginal: "Row Sum"})

    if TypeOf(result.(out_name)) = "null"
      then result.(out_name) = nz(v)
      else result.(out_name) = result.(out_name) + nz(v)
  end
  return(result)
endmacro

Macro "Summarize NHB" (MacroOpts)
  
  equiv = MacroOpts.equiv
  trip_bin = MacroOpts.trip_bin
  group = MacroOpts.group
  result = MacroOpts.result

  nhb = CreateObject("Table", trip_bin)
  flds = nhb.GetFieldNames()
  for fld in flds do
    parts = ParseString(fld, "_")
    mode = "default"
    if ArrayLength(parts) = 3 then mode = parts[2] else if ArrayLength(parts) = 4 then mode = parts[3] else if ArrayLength(parts) = 5 then mode = "auto_pay"// set mode
    if equiv.(mode) = null then continue // if fld is not trip fields
    if group = "PM" and right(fld, 2) <> "PM" then continue // if group = PM then only add PM flds
    
    out_name = equiv.(mode) + "_" + group
    v = nhb.(fld)
    v.rowbased = "false"
    if TypeOf(result.(out_name)) = "null"
        then result.(out_name) = nz(v)
        else result.(out_name) = result.(out_name) + nz(v)
  end
  return(result)

endmacro