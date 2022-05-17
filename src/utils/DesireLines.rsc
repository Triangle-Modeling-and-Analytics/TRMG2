/*
A tool to facilitate desire line map creation for the currently-selected
scenario.
*/

// Desire Line Toolbox
Macro "Open Desire Lines Dbox" (Args)
	RunDbox("DesireLines", Args)
endmacro
dBox "DesireLines" (Args) center,center,90,17 toolbox NoKeyboard Title:"Desire Line Toolbox"

	Init do	
		// Input Files
		scen_folder = Args.[Scenario Folder] + "\\"
		taz_file = scen_folder + "output\\tazs\\scenario_tazs.dbd"
		hwy_file = scen_folder + "output\\networks\\scenario_links.dbd"
		hwy_file = scen_folder + "output\\networks\\scenario_links.dbd"

		static type, agg, int3, tod, int4, mode
		static typehelp, agghelp, todhelp, modehelp
		static map, taz_lyr
		{map_names, , } = GetMaps()
		if map_names.position(map) = 0 then do
			map = null
			taz_lyr = null
		end else do
			SetWindow(map)
			SetMap(map)
			SetLayer(taz_lyr)
		end
	enditem
	
	// Origin or Destination drop down menu
	Popdown Menu "O/D" 2, 2, 24, 8 prompt: "1. Origin or Destination" list: {"Origin","Destination"} variable: type do
		if type = 1 then typehelp = "\"I want to see trip originating from"
		else typehelp = "\"I want to see trips destined to"
	enditem 
	
	// Aggregation drop down menu
	Popdown Menu "agg" 2, 4, 24, 8 prompt: "2. Aggregation" list: {"Zones","District"} variable: agg do
		if agg = 1 then agghelp = "the zones I select.\""
		else agghelp = "the zones I select aggregated to a district.\""
	enditem 
	
	//	Create Selection Set Button
	button "3. Create Selection Set" 1.5,6,22 do	
		ShowMessage("Fill \"Selection\" with your zones of interest. \nLeave the map open.")

		{map_names, , } = GetMaps()
		if map_names.position(map) = 0 then do
			map = null
			taz_lyr = null
			{map, {taz_lyr}} = RunMacro("Create Map", {file: taz_file, minimized: "false"})
			SetLayer(taz_lyr)
		end else do
			SetWindow(map)
			SetMap(map)
			SetLayer(taz_lyr)
		end
	enditem
	
	// TOD drop down menu
	Popdown Menu "Dist" 2, 8, 24, 8 prompt: "4. Time of Day" list: {"AM Peak","Mid Day","PM Peak","Night"} variable: int3 do
		if int3 = 1 then tod = "AM"
		else if int3 = 2 then tod = "MD"
		else if int3 = 3 then tod = "PM"
		else tod = "NT"
		
		todhelp = "\"I want to see trips in the " + tod + " period.\""
	enditem 
	
	// Mode drop down menu
	Popdown Menu "Mode" 2, 10, 24, 8 prompt: "5. Mode" list: {"Auto","Transit","Truck","Non Motorized"} variable: int4 do
		if int4 = 1 then mode = "Auto"
		else if int4 = 2 then mode = "Transit"
		else if int4 = 3 then mode = "Truck"
		else mode = "BikeWalk"
		
		modehelp = "\"Show trips for the " + mode + " mode.\""
	enditem 	
	
	Radio List "Help" 28,.75,43,10.5 Prompt: "Help"

	// Help text boxes
	Text" " 30.5,2,40,1 Variable:typehelp
	Text" " 30.5,4,40,1 Variable:agghelp
	Text" " 30.5,8,40,1 Variable:todhelp
	Text" " 30.5,10,40,1 Variable:modehelp

	// Create Map Button
	button "Create Map" 9,15.5,12 do
		if type = null or agg = null or int3 = null or int4 = null then
			ShowMessage("Please make a selection for all drop down lists.")
		else if GetMapNames() = null then
			ShowMessage("Use step 3 to create a map and selection set.")
		else if GetSetCount("Selection") = 0 then
			ShowMessage("Use the map to choose TAZs for the set \"Selection\"")
		else
			RunMacro("DesireLines2", Args, taz_file, type, agg, tod, mode, taz_lyr)
		
	enditem

	// Quit Button
	button "Quit" 30, 15.5, 12 do
		Return(0)
	enditem
EndDbox


Macro "DesireLines2" (Args, taz_file, type, agg, tod, mode, taz_lyr)
	
	// Input Variables
	scen_folder = Args.[Scenario Folder] + "\\"
	out_dir = Args.[Output Folder]
	if mode = "Auto" or mode = "Truck" 
		then mtx_file = out_dir + "/assignment/roadway/od_veh_trips_" + tod + ".mtx"
	if mode = "Transit" then mtx_file = out_dir + "/assignment/transit/transit_" + tod + ".mtx"
	if mode = "BikeWalk" then mtx_file = out_dir + "/resident/nonmotorized/nm_gravity.mtx"
	if type = 1 then type = "Orig"
	else if type = 2 then type = "Dest"
	if agg = 1 then agg = "Zone"
	else if agg = 2 then agg = "Dist"
	
	// Output Variables
	outputFolder = out_dir + "/_summaries/DesireLines/" + tod + "\\" + mode
	RunMacro("Create Directory", outputFolder)
	outputFolder = outputFolder + "\\"
	desirelinedbd = outputFolder + type + "Based" + tod + mode + "DesireLines.dbd"
	districtdbd = outputFolder + type + "Based" + tod + mode + "Districts.dbd"
	flowmtx = outputFolder + type + "Based" + tod + mode + "OD.mtx"
	
	// District Creation
	a_fields =  {{"tempdist", "Integer", 10, ,,,, ""}}
	RunMacro("Add Fields", {view: taz_lyr, a_fields: a_fields})
	
	// Copy over the current district values
	v_curdist = GetDataVector(taz_lyr + "|", "District2", )
	SetDataVector(taz_lyr + "|", "tempdist", v_curdist, )
	
	// Create new district values for the user-selected taz
	v_newdist = GetDataVector(taz_lyr + "|Selection", "tempdist", )
	for i = 1 to v_newdist.length do
		// If aggregating selected zones to a single district, then they all 
		// get a new district value of 100. Otherwise, give them new, but 
		// different district numbers (101, 102, etc.)
		if agg = "Dist" then do
			v_newdist[i] = 100
		end else if agg = "Zone" then do
			v_newdist[i] = 100 + i
		end
	end
	SetDataVector(taz_lyr + "|Selection", "tempdist", v_newdist, )
	
	// Merge the TAZs into a district layer based on the tempdist field
	MergeByValue(
		districtdbd, "Districts", taz_lyr + "|", "tempdist", "FFB", ,
		{{"Missing as Zero"}}
	)

	// Determine cores of interest based on mode selected
	mtx = CreateObject("Matrix", mtx_file)
	if mode = "Auto" then a_corenames = {"sov", "hov2", "hov3", "CV"}
	else if mode = "Transit" then a_corenames = mtx.GetCoreNames()
	else if mode = "Truck" then a_corenames = {"SUT", "MUT"}
	else if mode = "BikeWalk" then do
		a_corenames = mtx.GetCoreNames()
		a_corenames = ExcludeArrayElements(a_corenames, 8, a_corenames.length - 7)
	end
	
	// Create new matrix core and set all values to 0
	mtx.AddCores({mode})
	target = mtx.GetCore(mode)
	target := 0
	
	// Add cores of interest into new core
	for core_name in a_corenames do
		core = mtx.GetCore(core_name)
		target := target + core
	end
	
	// Aggregate matrix based on the new district designation in the TAZ layer
	Opts = null
	Opts.[File Name] = flowmtx
	Opts.Label = tod + " " + mode + " District Flows"
	matrix_final = AggregateMatrix(target, {taz_lyr+".ID", taz_lyr+".tempdist"}, {taz_lyr+".ID", taz_lyr+".tempdist"}, Opts)
	mtx_final = CreateObject("Matrix", matrix_final)
	matrix_final = null
	// Note: not sure why the class approach isn't working. Could debug later.
	// agg_mtx = mtx.Aggregate({
	// 	Matrix: {FileName: flowmtx, MatrixLabel: "Aggregated " + mode + " " + tod + " flows"},
	// 	Method: "Sum",
	// 	Matrices: {mode},
	// 	Rows: {
	// 		ViewName: taz_lyr,
	// 		MatrixID: "ID",
	// 		AggregationID: "tempdist"
	// 	},
	// 	Cols: {
	// 		ViewName: taz_lyr,
	// 		MatrixID: "ID",
	// 		AggregationID: "tempdist"
	// 	}
	// })

	// Creating Desire Lines

	// Create a map of the district layer
	{out_map, {district_lyr}} = RunMacro("Create Map", {file: districtdbd, minimized: "false"})
	SetMap(out_map)
	SetLayer(district_lyr)
	
	// Create a currency for the aggregated matrix
	mtxcur_final = mtx_final.GetCore(mode)
	
	// Select the district(s) of interest
	if agg = "Dist" then query = "Select * where tempdist = 100"
	else if agg = "Zone" then do
		query = "Select * where "
		for i = 1 to v_newdist.length do
			query = query + "tempdist = " + i2s(v_newdist[i])
			if i < v_newdist.length then query = query + " or "
		end
	end
	n1 = SelectByQuery("Selection","Several",query)
	
	// Setup the Origin vs Destination option
	if type = "Orig" then do
		rowlyrset = district_lyr + "|Selection"
		collyrset = district_lyr + "|"
	end
	else if type = "Dest" then do
		rowlyrset = district_lyr + "|"
		collyrset = district_lyr + "|Selection"
	end
	
	// Create Desire Lines
	Opts = null
	Opts.[Layer Name] = type + " " + tod + " " + mode + " " + "Desire"
	CreateDesirelineDB(desirelinedbd, {mtxcur_final}, rowlyrset, collyrset, "tempdist", Opts)
	
	// Add the desire lines to the map
	layers = GetDBLayers(desirelinedbd)
	lLayer = AddLayer(out_map,layers[2],desirelinedbd,layers[2])
	SetLayer(lLayer)
	SetLineWidth(lLayer + "|",.25)
	
	// Dualized Scaled Symbol Theme
	flds = {lLayer + ".AB"}
	opts = null
	opts.Title = "AB/BA Desire Lines"
	opts.[Data Source] = "Screen"
	//opts.[Minimum Value] = 0
	//opts.[Maximum Value] = 100
	opts.[Minimum Size] = 2
	opts.[Maximum Size] = 12
	dual_colors = {ColorRGB(32000,32000,65535)}
	dual_linestyles = {LineStyle({{{2, -1, 0},{0,0,1},{0,0,-1}}})}
	dual_labels = {"AB"}
	dual_linesizes = {3}
	theme_name = CreateContinuousTheme("Desire Lines", flds, opts)
	SetThemeLineStyles(theme_name , dual_linestyles)
	SetThemeClassLabels(theme_name , dual_labels)
	SetThemeLineColors(theme_name , dual_colors)
	SetThemeLineWidths(theme_name , dual_linesizes)
	ShowTheme(, theme_name)
	SetLegendDisplayStatus(theme_name, "False")
	RedrawMap()	
	
	// Configure Legend
	str1 = "XXXXXXXX"
	solid = FillStyle({str1, str1, str1, str1, str1, str1, str1, str1})
	if type = "Orig" then title = "Trips Originating from Selected"
	else if type = "Dest" then title = "Trips Destined to Selected"
	if agg = "Zone" then title = title + " Zones"
	else if agg = "Dist" then title = title + " District"
	footnote = "(" + type + " " + agg + " " + tod + " " + mode + ")"
	CreateLegend(out_map,{"Automatic",
		{0,1,0,1,1,0},
		{1,1,1},
		{"Arial|16", "Arial|9", "Arial|16", "Arial|12"},
		{title, footnote}
	},{
		{"Background Color", ColorRGB(65535, 65535, 65535)},
		{"Background Style", solid}
	})
	
	// Change the order so that the selection set info comes after the layer info
	//SetLegendItemPosition(map, 1, 2)

	// Rename the selection set label in legend
	SetLayer("Districts")
	if agg = "Dist" then RenameSet("Selection",type + " District")
	if agg = "Zone" then RenameSet("Selection",type + " Zone(s)")
	SetLayerSetsLabel("Districts", type + " District(s)", "False")
	
	ShowLegend(out_map)
	
	map_file = outputFolder + type + "Based" + tod + mode + agg + ".map"
	SaveMap(out_map, map_file)
	ShowMessage("This map has been saved to\n" + map_file)
EndMacro