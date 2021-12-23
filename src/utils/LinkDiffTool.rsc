/*
Simple macro needed by the flowchart to open the dbox
*/

Macro "Open Diff Tool"
  RunDbox("link_diff_tool")
endmacro

/*
A tool for looking at changes between two link layers.
*/

dBox "link_diff_tool" center, center, 40, 8 Title: "Link Diff Tool" Help: "test" toolbox

  init do
    static old_dbd, new_dbd
  enditem

  close do
    return()
  enditem

  Text 15, 2, 15 Framed Prompt: "Old/Base DBD:" Variable: old_dbd
  Button after, same, 5, 1 Prompt: "..." do
    on error, escape goto skip1
    old_dbd = ChooseFile({{"line layer", "*.dbd"}}, "Choose old line layer", )
    skip1:
    on error default
  enditem

  Text 15, after, 15 Framed Prompt: "New DBD:" Variable: new_dbd
  Button after, same, 5, 1 Prompt: "..." do
    on error, escape goto skip2
    new_dbd = ChooseFile({{"line layer", "*.dbd"}}, "Choose new line layer", )
    skip2:
    on error default
  enditem

  Button 8, 6 Prompt: "Diff Layers" do
    RunMacro("Diff Line Layers", {old_dbd: old_dbd, new_dbd: new_dbd})
  enditem
  Button 20, same Prompt: "Quit" do
    Return()
  enditem
  Button 28, same Prompt: "Help" do
    ShowMessage(
      "This tool is used to track changes between two link layers. " +
      "It tracks both spatial and attribute changes. After selecting the " +
      "base and new link layers, two maps will be created highlighting these " +
      "differences.\n\n" +
      "Note: fields are added to the new link layer to track attribute changes"
    )
  enditem
enddbox

/*
This macro diff two versions of the same network highlighting things like
new, deleted, or modified links.

Inputs
  * old_dbd
    * The old/before line layer (dbd)
  * new_dbd
    * The new/after line layer (dbd)

Returns
  * Creates maps of the old and new line layers and color codes by change type
  * Adds fields to `new_dbd` to mark new links, previous attribute values, etc
*/

Macro "Diff Line Layers" (MacroOpts)

  old_dbd = MacroOpts.old_dbd
  new_dbd = MacroOpts.new_dbd
	set_line_width = 1.5

  // Create separate maps for both dbds
  {new_map, {new_nlyr, new_llyr}} = RunMacro("Create Map", {file: new_dbd, map_name: "new layer"})
  {old_map, {old_nlyr, old_llyr}} = RunMacro("Create Map", {file: old_dbd, map_name: "old layer"})
  // Handle duplicate layer names
  if Position(old_nlyr, ":") > 0 then do
    RenameLayer(old_nlyr, "old_nodes", )
    old_nlyr = "old_nodes"
  end
  if Position(old_llyr, ":") > 0 then do
    RenameLayer(old_llyr, "old_links", )
    old_llyr = "old_links"
  end

  // Get field info for both line layers
  {new_fld_names, new_fld_specs} = RunMacro("Get Fields", {view_name: new_llyr})
  {old_fld_names, old_fld_specs} = RunMacro("Get Fields", {view_name: old_llyr})

	// Select deleted links
	SetMap(old_map)
	SetLayer(old_llyr)
  // check if the sets already exist, so that you don't end up with :1, :2
  // Selection sets are shared across maps on the same layer, so even with a
  // a fresh map, it could already exist. E.g. if running the tool twice.
  deleted_set = "Deleted"
  if ArrayPosition(GetSets(), {deleted_set},) > 0 
    then SelectNone(deleted_set)
    else deleted_set = RunMacro("G30 create set", deleted_set)
	SetLineColor(old_llyr + "|" + deleted_set, ColorRGB(55255, 6425, 7196))
	SetLineWidth(old_llyr + "|" + deleted_set, set_line_width)
  jv = JoinViews("jv", old_fld_specs.ID, new_fld_specs.ID, )
	SetView(jv)
  query = "Select * where " + new_fld_specs.ID + " = null"
	n = SelectByQuery(deleted_set, "several", query)
	CloseView(jv)

	// Add fields to the new line layer
  a_fields = {
		{"diff_fields", "Character", 16, , , , , "Marks the start of fields added|by the diff tool"},
		{"diff_new", "Integer", 10, , , , , "New links marked with a 1"},
		{"diff_modified", "Integer", 10, , , , , "Links with spatial modifications|marked with a 1"},
		{"diff_att_mod", "Integer", 10, , , , , "Links with attribute modifications|marked with a 1"}
	}
    RunMacro("Add Fields", new_llyr, a_fields, {"--------------->", null})

  // Mark new links
	SetMap(new_map)
	SetLayer(new_llyr)
  new_set = "Added"
  if ArrayPosition(GetSets(), {new_set},) > 0 
    then SelectNone(new_set)
    else new_set = RunMacro("G30 create set", new_set)
	SetLineColor(new_llyr + "|" + new_set, ColorRGB(6682, 38550, 16705))
	SetLineWidth(new_llyr + "|" + new_set, set_line_width)
  jv = JoinViews("jv", new_fld_specs.ID, old_fld_specs.ID, )
	SetView(jv)
	query = "Select * where " + old_fld_specs.ID + " = null"
	n = SelectByQuery(new_set, "several", query)
	if n > 0 then do
		v = Vector(n, "Long", {Constant: 1})
		SetDataVector(jv + "|" + new_set, "diff_new", v, )
	end

	// Mark links with spatial modifications
	// Compare link lengths to find differences. The chance of manual changes
	// ending up at the exact same length are so small they can be ignored.
	SetMap(new_map)
	SetLayer(new_llyr)
  spatial_set = "Spatial Changes"
  if ArrayPosition(GetSets(), {spatial_set},) > 0 
    then SelectNone(spatial_set)
    else spatial_set = RunMacro("G30 create set", spatial_set)
	SetLineColor(new_llyr + "|" + spatial_set, ColorRGB(59110, 24929, 1))
	SetLineWidth(new_llyr + "|" + spatial_set, set_line_width)
  query = "Select * where " + old_fld_specs.[Length] + " <> " + new_fld_specs.[Length]
	n = SelectByQuery(spatial_set, "several", query, {"Source Not": new_set})
	if n > 0 then do
		v = Vector(n, "Long", {Constant: 1})
		SetDataVector(jv + "|" + spatial_set, "diff_modified", v, )
	end

	// Find links with attribute differences and catalog those differences
	SetMap(new_map)
	SetLayer(new_llyr)
  att_setname = "Attribute Changes"
  if ArrayPosition(GetSets(), {att_setname},) > 0 
    then SelectNone(att_setname)
    else att_setname = RunMacro("G30 create set", att_setname)
	SetLineColor(new_llyr + "|" + att_setname, ColorRGB(65021, 47288, 25443))
	SetLineWidth(new_llyr + "|" + att_setname, set_line_width)
	SetView(jv)
	temp_set = CreateSet("temp_set")
	SetOR("temp_set", {new_set})
	SetInvert(temp_set, temp_set)
	{, a_field_specs} = GetFields(jv, "All")
	data = GetDataVectors(jv + "|" + temp_set, a_field_specs, {OptArray: "true"})
	CloseView(jv) // will be modifying columns in the loop
  v_any_at_change = Vector(GetSetCount(temp_set), "Long", )
	for i = 1 to data.length do
		// To avoid processing duplicate fields twice, skip any from the
		// old_llyr. Also skip ID, Length, and the diff fields added by this
		// macro.
		field_spec = data[i][1]
		if Right(field_spec, 3) = ".ID" then continue
		if Right(field_spec, 7) = ".Length" then continue
		if Position(field_spec, new_llyr) = 0 then continue

		{, , field_name} = ParseString(field_spec, ".")
		old_field = "jv." + old_llyr + "." + field_name
		new_field = "jv." + new_llyr + "." + field_name
		v_tf = if data.(old_field) <> data.(new_field)
			then 1
			else 0
    // keep track of changes across fields in order to mark links with any
    // attributes changed.
    v_any_at_change = if v_tf = 1 then 1 else v_any_at_change
		if VectorStatistic(v_tf, "sum", ) > 0 then do
			field_type = data.(old_field).type
			if ArrayPosition({"integer", "short", "long"}, {field_type}, ) then type = "Integer"
			else if field_type = "string" then type = "Character"
			else type = "Real"
      // create the name of the field to hold the previous values
      if Right(field_name, 1) = "]" then do
        temp1 = Substitute(field_name, "[", "", 1)
        temp2 = Substitute(temp1, "]", "", 1)
        prev_field_name = "prev_" + temp2
      end else prev_field_name = "prev_" + field_name
      a_fields = {{prev_field_name, type, 10, 2, , , , "Previous value for the '" + field_name + "' field."}}
      RunMacro("Add Fields", new_llyr, a_fields, )
			v_temp = if v_tf = 1 then data.(old_field)
			diff_data.(prev_field_name) = v_temp
		end
	end
	if diff_data <> null then do
		jv = JoinViews("jv", new_fld_specs.ID, old_fld_specs.ID, )
		SetDataVectors(jv + "|" + temp_set, diff_data, )
		CloseView(jv)
	end
  SetDataVector(new_llyr + "|" + temp_set, "diff_att_mod", v_any_at_change, )
  SetLayer(new_llyr)
  DeleteSet(temp_set)
  query = "Select * where diff_att_mod <> null"
  SelectByQuery(att_setname, "several", query)


  SetMap(new_map)
  SetLayer(new_llyr)
	SetSetPosition(spatial_set, 3)

	// Configure Legend
	SetMap(old_map)
	SetLayerSetsLabel(old_llyr, "Changes", "true")
	SetMap(new_map)
	SetLayerSetsLabel(new_llyr, "Changes", "true")
	maps = {old_map, new_map}
	for map in maps do
		SetMap(map)
		RunMacro("G30 create legend")
		SetLegendSettings (
		GetMap(),
		{
			"Automatic",
			{0, 0, 0, 1, 1, 4, 0},
			{1, 1, 1},
			{"Arial|Bold|16", "Arial|9", "Arial|Bold|16", "Arial|12"},
			{"", }
		}
		)
		str1 = "XXXXXXXX"
		solid = FillStyle({str1, str1, str1, str1, str1, str1, str1, str1})
		SetLegendOptions (GetMap(), {{"Background Style", solid}})
		ShowLegend(GetMap())
	end

	//Arrange Windows
  {flow_chart, , } = GetWindows("COM Control")
  if flow_chart <> null then MinimizeWindow(flow_chart[1])
	{windows, , } = GetWindows("Map")
	for window in windows do
		RestoreWindow(window)
	end
	TileWindows()
endmacro

/*
Adds a field.

  * view
    * String
    * view name
  * a_fields
    * Array of arrays
    * Each sub-array contains the 12-elements that describe a field.
      e.g. {{"Density", "Real", 10, 3, , , , "Used to calculate initial AT"}}
      (See ModifyTable() TC help page for full array info)
  * initial_values
    * Number, string, or array of numbers/strings (optional)
    * If not provided, any fields to add that already exist in the table will not be
      modified in any way. If provided, the added field will be set to this value.
      This can be used to ensure that a field is set to null, zero, etc. even if it
      already exists.
    * If a single value, it will be used for all fields.
    * If an array shorter than number of fields, the last value will be used
      for all remaining fields.
*/

Macro "Add Fields" (view, a_fields, initial_values)

  // Argument check
  if view = null then Throw("'view' not provided")
  if a_fields = null then Throw("'a_fields' not provided")
  for field in a_fields do
    if field = null then Throw("An element in the 'a_fields' array is missing")
  end
  if initial_values <> null then do
    if TypeOf(initial_values) <> "array" then initial_values = {initial_values}
    if TypeOf(initial_values) <> "array"
      then Throw("'initial_values' must be an array")
  end

  // Get current structure and preserve current fields by adding
  // current name to 12th array position
  a_str = GetTableStructure(view)
  for s = 1 to a_str.length do
    a_str[s] = a_str[s] + {a_str[s][1]}
  end
  for f = 1 to a_fields.length do
    a_field = a_fields[f]

    // Test if field already exists (will do nothing if so)
    field_name = a_field[1]
    exists = "False"
    for s = 1 to a_str.length do
      if a_str[s][1] = field_name then do
        exists = "True"
        break
      end
    end

    // If field does not exist, create it
    if !exists then do
      dim a_temp[12]
      for i = 1 to a_field.length do
        a_temp[i] = a_field[i]
      end
      a_str = a_str + {a_temp}
    end
  end

  ModifyTable(view, a_str)

  // Set initial field values if provided
  if initial_values <> null then do
    nrow = GetRecordCount(view, )
    for f = 1 to a_fields.length do
      field = a_fields[f][1]
      type = a_fields[f][2]
      if f > initial_values.length
        then init_value = initial_values[initial_values.length]
        else init_value = initial_values[f]

      if type = "Character" then type = "String"

      opts = null
      opts.Constant = init_value
      v = Vector(nrow, type, opts)
      SetDataVector(view + "|", field, v, )
    end
  end
EndMacro

/*
Macro to simplify the process of map creation.

Inputs
  MacroOpts
    Named array that holds argument names

    file
      String
      Full path to the file to map. Supported types:
        Point, Line, Polygon geographic files. RTS files.

	map_name
	  Optional String
	  Desired name for the map. Actual map named returned may be different
	  if there is a map with the same name. By default, a unique name is
	  created

    minimized
      Optional String ("true" or "false")
      Defaults to "true".
      Whether to minimize the map. Makes a number of geospatial calculations
      faster if the map does not have to be redrawn.

Returns
  An array of two things:
  1. the name of the map
  2. an array of layer names
    * for dbd files: {node, link}
    * for rts files: {route, stops, phys. stops, node, link}
*/

Macro "Create Map" (MacroOpts)

  // Argument extraction
  file = MacroOpts.file
  map_name = MacroOpts.map_name
  minimized = MacroOpts.minimized

  // Argument checking
  if file = null then Throw("Create Map: 'file' not provided")
  if minimized = null then minimized = "true"

  // Determine file extension
  {drive, directory, filename, ext} = SplitPath(file)
  if Lower(ext) = ".dbd" then file_type = "dbd"
  else if Lower(ext) = ".rts" then file_type = "rts"
  else Throw("Create Map: 'file' must be either a '.dbd.' or '.rts' file")

  // Get a unique name for the map
  if map_name = null then do
  	map_name = RunMacro("Get Unique Map Name")
  end

  // Create the map if a dbd file was passed
  if file_type = "dbd" then do
    a_layers = GetDBLayers(file)
    {scope, label, rev} = GetDBInfo(file)
    opts = null
    opts.scope = scope
    map_name = CreateMap(map_name, opts)
    if minimized then MinimizeWindow(GetWindowName())
    for layer in a_layers do
      l = AddLayer(map_name, layer, file, layer)
      RunMacro("G30 new layer default settings", l)
      actual_layers = actual_layers + {l}
    end
  end

  // Create the map if a RTS file was passed
  if file_type = "rts" then do

    // Get the RTS's highway file
    opts = null
    opts.rts_file = file
    hwy_dbd = RunMacro("Get RTS Highway File", opts)
    {scope, label, rev} = GetDBInfo(hwy_dbd)
    opts = null
    opts.Scope = scope
    map = CreateMap(map_name, opts)
    if minimized then MinimizeWindow(GetWindowName())
    {, , opts} = GetRouteSystemInfo(file)
    rlyr = opts.Name
    actual_layers = AddRouteSystemLayer(map, rlyr, file, )
    if !minimized then do
      for layer in actual_layers do
        // Check for null - the physcial stops layer is often null
        if layer <> null then RunMacro("G30 new layer default settings", layer)
      end
    end
  end

  return({map_name, actual_layers})
EndMacro

/*
Helper to "Create Map" macro.
Avoids duplciating map names by using an odd name and checking to make
sure that map name does not already exist.

Similar to "unique_view_name" in gplyr.
*/

Macro "Get Unique Map Name"
  {map_names, idx, cur_name} = GetMaps()
  if map_names.length = 0 then do
    map_name = "map1"
  end else do
    num = 0
    exists = "True"
    while exists do
      num = num + 1
      map_name = "map" + String(num)
      exists = if (ArrayPosition(map_names, {map_name}, ) <> 0)
        then "True"
        else "False"
    end
  end

  return(map_name)
EndMacro

/*doc
Makes it easy to get properly bracketed field names and specs that you can
reference with simple field name strings.

Inputs
  * view_name
    * String
    * Name of view to get field info from
  * field_type
    * Optional string
    * Defaults to "All"
    * Field types to get info for
  * named_array
    * Boolean
    * Defaults to "true"
    * Whether to returned a named or flat list (see Returns)
  
Returns
  * If `named_array = "true"`
    * An array with two items
      * Named array of field names
      * Named array of field specs
  * If `named_array = "false"`
    * An array with two items
      * Simple array of field names
      * Simple array of field specs    
*/

Macro "Get Fields" (MacroOpts)

  view_name = MacroOpts.view_name
  field_type = MacroOpts.field_type
  named_array = MacroOpts.named_array

  if field_type = null then field_type = "All"
  if named_array = null then named_array = "true"

  {names, specs} = GetFields(view_name, field_type)
  
  if !named_array then return({names, specs})

  // Continue if returning a named array
  for i = 1 to names.length do
    name = names[i]
    spec = specs[i]

    array_name = if Left(name, 1) = "[" and Right(array_name, 1) = "]"
      then Substring(array_name, 2, StringLength(array_name) - 2)
      else name
    
    name_result.(array_name) = name
    spec_result.(array_name) = spec
  end
  return({name_result, spec_result})
endmacro
