/*
TODO: 
This code is a place holder for the tool, but has not been configured to
work with TRMG2.
*/

// Debug Macro
Macro "test"
	scenario_current_spec.name = "testingMLC2010"
	RunDbox("DesireLines", scenario_current_spec, "F:\\Models\\Reno")
EndMacro
	


// Desire Line Toolbox

dBox "DesireLines" (scenario_current_spec, model_directory) center,center,90,17 toolbox NoKeyboard Title:"Desire Line Toolbox"

	Init do	
		// Input Files
		scen_folder = model_directory + "\\scenarios\\" + scenario_current_spec.name + "\\"
		if scenario_current_spec.name = null then scen_folder = "F:\\Models\\Reno\\scenarios\\testingMLC2010\\"  //Can remove when incorporated
		//taz_file = scen_folder + "inputs\\gis\\taz\\taz.cdf"
		taz_file = scen_folder + "outputs\\mapping\\OutputTAZs\\OutputTAZ.cdf"
		hwy_file = scen_folder + "inputs\\gis\\streets\\streets.dbd"
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
		// Open the TAZ
			ShowMessage("Fill \"Selection\" with your zones of interest. \nLeave the map open.")
			RunMacro("G30 new map", taz_file, "False")
			layers = GetDBLayers(taz_file)
			SetLayer(layers[1])
	enditem
	
	// TOD drop down menu
	Popdown Menu "Dist" 2, 8, 24, 8 prompt: "4. Time of Day" list: {"AM Peak","Mid Day","PM Peak","Night"} variable: int3 do
		if int3 = 1 then tod = "am"
		else if int3 = 2 then tod = "md"
		else if int3 = 3 then tod = "pm"
		else tod = "nt"
		
		todhelp = "\"I want to see trips in the " + tod + " period.\""
	enditem 
	
	// Mode drop down menu
	Popdown Menu "Mode" 2, 10, 24, 8 prompt: "5. Mode" list: {"All","SOV","HOV","Bus","Truck","Non Motorized"} variable: int4 do
		if int4 = 1 then mode = "All"
		else if int4 = 2 then mode = "SOV"
		else if int4 = 3 then mode = "HOV"
		else if int4 = 4 then mode = "Bus"
		else if int4 = 5 then mode = "Truck"
		else mode = "BikeWalk"
		
		if int4 = 1 then modehelp = "\"Show trips for all modes\""
		else modehelp = "\"Show trips for the " + mode + " mode.\""
	enditem 	
	
	Radio List "Help" 28,.75,43,10.5 Prompt: "Help"

	//Frame 28,1.5, 20,11  Prompt: "Help"
	
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
			RunMacro("DesireLines2", scen_folder, taz_file, type, agg, tod, mode, layers)
		
	enditem

	// Quit Button
	button "Quit" 30, 15.5, 12 do
		Return(0)
	enditem
EndDbox


Macro "DesireLines2" (scen_folder, taz_file, type, agg, tod, mode, layers)
	
	// Input Variables
	taz_lyr = layers[1]
	mtx_file = scen_folder + "outputs\\tod\\trips_" + tod + ".mtx"	
	if type = 1 then type = "Orig"
	else if type = 2 then type = "Dest"
	if agg = 1 then agg = "Zone"
	else if agg = 2 then agg = "Dist"
	
	// Output Variables
	outputFolder = scen_folder + "outputs\\mapping\\DesireLines\\" + Upper(tod) + "\\" + mode + "\\"
		on error goto skipfolder
		CreateDirectory(scen_folder + "outputs\\mapping\\DesireLines\\" + Upper(tod) + "\\" + mode)
		skipfolder:
		on error default
	
	desirelinedbd = outputFolder + type + "Based" + Upper(tod) + mode + "DesireLines.dbd"
	districtdbd = outputFolder + type + "Based" + Upper(tod) + mode + "Districts.dbd"
	flowmtx = outputFolder + type + "Based" + Upper(tod) + mode + "OD.mtx"
	
	// District Creation
	
	// Add a new TAZ ID and District ID field to the TAZ if they don't already exist
	a_fnames = GetFields(taz_lyr,"All")
	a_fnames = a_fnames[1]
	
	if ArrayPosition(a_fnames,{"ODtaz"},) = 0 then do
		
		strct = GetTableStructure(taz_lyr)	
		for i = 1 to strct.length do
			strct[i] = strct[i] + {strct[i][1]}	
		end	
		
		// This is where you add fields by appending them onto strct
		strct = strct + {{"ODtaz", "Integer", 12, 2, "False", , , , , , , null}}
		strct = strct + {{"tempdist", "Integer", 12, 2, "False", , , , , , , null}}
		ModifyTable(taz_lyr, strct)
	end
	
	// Setup the ODtaz field to increment by 1 starting at 8
	// This ensure it matches the Row and Column index in the TOD matrices later on
	v_odtaz = GetDataVector(taz_lyr + "|", "taz", {{"Sort Order",{{"taz","Ascending"}}}})
	for i = 1 to v_odtaz.length do
		v_odtaz[i] = 7 + i
	end
	SetDataVector(taz_lyr + "|", "ODtaz", v_odtaz, {{"Sort Order",{{"taz","Ascending"}}}})
	
	// Copy over the current district values
	v_curdist = GetDataVector(taz_lyr + "|", "district", {{"Sort Order",{{"taz","Ascending"}}}})
	SetDataVector(taz_lyr + "|", "tempdist", v_curdist, {{"Sort Order",{{"taz","Ascending"}}}})
	
	// Create new district values for the user-selected taz
	v_newdist = GetDataVector(taz_lyr + "|Selection", "tempdist", {{"Sort Order",{{"taz","Ascending"}}}})
	
	for i = 1 to v_newdist.length do
		// If aggregating selected zones to a single district, then they all get a new district value of 100
		// Otherwise, give them new, but different district numbers (101, 102, etc.)
		if agg = "Dist" then do
			v_newdist[i] = 100
		end
		else if agg = "Zone" then do
			v_newdist[i] = 100 + i
		end
	end
	
	SetDataVector(taz_lyr + "|Selection", "tempdist", v_newdist, {{"Sort Order",{{"taz","Ascending"}}}})
	
	// Merge the TAZs into a district layer based on the tempdist field
	MergeByValue(districtdbd, "Districts", taz_lyr + "|", "tempdist", "FFB", 
		{
			{"acres","sum"},
			{"households","sum"},
			{"low_income_hhs_fraction","sum"},
			{"medium_income_hhs_fraction","sum"},
			{"high_income_hhs_fraction","sum"},
			{"population_hh","sum"},
			{"population_gq","sum"},
			{"hh_size_1","sum"},
			{"hh_size_2","sum"},
			{"hh_size_3","sum"},
			{"hh_size_4","sum"},
			{"hh_size_5","sum"},
			{"hh_size_6","sum"},
			{"hh_size_7plus","sum"},
			{"population_0_19","sum"},
			{"population_20_54","sum"},
			{"population_55plus","sum"},
			{"enroll_elementary","sum"},
			{"enroll_secondary","sum"},
			{"enroll_university","sum"},
			{"emp_amc","sum"},
			{"emp_mtcuw","sum"},
			{"emp_r","sum"},
			{"emp_so","sum"},
			{"emp_g","sum"},
			{"emp_o","sum"},
			{"hotel_rooms","sum"},
			{"OrigAMVMT","sum"},
			{"OrigAMVHT","sum"},
			{"OrigMDVMT","sum"},
			{"OrigMDVHT","sum"},
			{"OrigPMVMT","sum"},
			{"OrigPMVHT","sum"},
			{"OrigNTVMT","sum"},
			{"OrigNTVHT","sum"},
			{"DestAMVMT","sum"},
			{"DestAMVHT","sum"},
			{"DestMDVMT","sum"},
			{"DestMDVHT","sum"},
			{"DestPMVMT","sum"},
			{"DestPMVHT","sum"},
			{"DestNTVMT","sum"},
			{"DestNTVHT","sum"}
		},
		{{"Missing as Zero"}}
	)

	// ----------------------
	//
	//		Matrix Setup
	//
	// ----------------------
	
	// Determine cores of interest based on mode selected
	if mode = "All" then a_corenames = {
		"pnr_express_bus",
		"da",
		"walk_express_bus",
		"bike",
		"knr_local_bus",
		"pnr_local_bus",
		"walk_local_bus",
		"sr2",
		"walk",
		"knr_express_bus",
		"sr3",
		"singleUnitTrucks",
		"multiUnitTrucks"
	}

	else if mode = "SOV" then a_corenames = {"da"}

	else if mode = "HOV" then a_corenames = {"sr2", "sr3"}

	else if mode = "Bus" then a_corenames = {
		"pnr_express_bus",
		"walk_express_bus",
		"knr_local_bus",
		"pnr_local_bus",
		"walk_local_bus",
		"knr_express_bus"
	}

	else if mode = "Truck" then a_corenames = {"singleUnitTrucks", "multiUnitTrucks"}

	else if mode = "BikeWalk"  then a_corenames = {"walk"}

	// Open Matrix
	matrix = OpenMatrix(mtx_file,)
	
	// Add the new core if it doesn't already exist
	a_existcorenames = GetMatrixCoreNames(matrix)
	if ArrayPosition(a_existcorenames, {mode},) = 0 then AddMatrixCore(matrix, mode)
	
	// Create new matrix core and set all values to 0
	mtxcur_new = CreateMatrixCurrency(matrix, mode, "Row index", "Column index",)
	mtxcur_new := 0
	
	// Add cores of interest into new core
	for i = 1 to a_corenames.length do
		mtxcur_temp = CreateMatrixCurrency(matrix, a_corenames[i], "Row index", "Column index",)
		mtxcur_new := mtxcur_new + mtxcur_temp
	end
	
	// Aggregate matrix based on the new district designation in the TAZ layer
	Opts = null
	Opts.[File Name] = flowmtx
	Opts.Label = Upper(tod) + " " + mode + " District Flows"
	matrix_final = AggregateMatrix(mtxcur_new, {taz_lyr+".ODtaz",taz_lyr+".tempdist"}, {taz_lyr+".ODtaz",taz_lyr+".tempdist"}, Opts)
	
	//		Creating Desire Lines
	
	// Close the current map
	maps = GetMapNames()
	for i = 1 to maps.length do
		 CloseMap(maps[i])
		 end
	
	// Create a map of the district layer
	map = RunMacro("G30 new map", districtdbd, "False")
	layers = GetDBLayers(districtdbd)
	district_lyr = layers[1]
	SetLayer(district_lyr)	
	
	// Create a currency for the aggregated matrix
	mtxcur_final = CreateMatrixCurrency(matrix_final, mode, "tempdist", "tempdist",)
	
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
	Opts.[Layer Name] = type + " " + Upper(tod) + " " + mode + " " + "Desire"
	CreateDesirelineDB(desirelinedbd, {mtxcur_final}, rowlyrset, collyrset, "tempdist", Opts)
	
	// Add the desire lines to the map
	//SetMap(map)
	//{node_lyr,link_lyr} = RunMacro("TCB Add DB Layers", desirelinedbd,,)
	layers = GetDBLayers(desirelinedbd)
	lLayer = AddLayer(map,layers[2],desirelinedbd,layers[2])
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
	//dual_linestyles = {LineStyle({{{1, -1, 0}}})}  //from caliper
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
	
	CreateLegend(map,{"Automatic",
		{0,1,0,1,1,0},
		{1,1,1},
		{"Arial|16", "Arial|9", "Arial|16", "Arial|12"},
		{title,"footnote location if needed"}
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
	
	ShowLegend(map)
	
	SaveMap(map, outputFolder + type + "Based" + Upper(tod) + mode + "Map.map")
	ShowMessage("This map has been saved to " + outputFolder)
EndMacro