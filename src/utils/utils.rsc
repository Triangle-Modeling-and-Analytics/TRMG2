/*
Closes any views and maps
*/

Macro "Close All" (scen_dir)

  // Close maps
  maps = GetMapNames()
  if maps <> null then do
    for i = 1 to maps.length do
      CloseMap(maps[i])
    end
  end

  // Close any views
  RunMacro("TCB Init")
  RunMacro("G30 File Close All")
endMacro

/*
Adds a field to a view.

  * `MacroOpts`
    * named array of function arguments
    * `view`
      * String
      * view name
    * `a_fields`
      * Array of arrays
      * Each sub-array contains the 12-elements that describe a field.
        e.g. {{"Density", "Real", 10, 3, , , , "Used to calculate initial AT"}}
        (See ModifyTable() TC help page for full array info)
    * `initial_values`
      * Number, string, or array of numbers/strings (optional)
      * If not provided, any fields to add that already exist in the table will not be
        modified in any way. If provided, the added field will be set to this value.
        This can be used to ensure that a field is set to null, zero, etc. even if it
        already exists.
      * If a single value, it will be used for all fields.
      * If an array shorter than number of fields, the last value will be used
        for all remaining fields.
*/

Macro "Add Fields" (MacroOpts)

  // Argument extraction
  view = MacroOpts.view
  a_fields = MacroOpts.a_fields
  initial_values = MacroOpts.initial_values

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
Checks that a file argument is valid.

Inputs (in named array)
  * file
    * The file to be checked
  * required
    * True/False: if the argument is required (by the parent macro).
  * must_exist
    * True/False: if the file must exist
  * extension
    * Optional string specifying a required extension (e.g. "dbd")

Returns
  * The file string
*/

Macro "check file" (MacroOpts)

  arg = MacroOpts.file
  required = MacroOpts.required
  must_exist = MacroOpts.must_exist
  extension = MacroOpts.extension

  if TypeOf(arg) = "null" then do
    if required 
      then Throw("An argument was not provided or is null.")
      else return()
  end
  if TypeOf(arg) <> "string" then Throw("A file path must be a string")
  if GetFileInfo(arg) = null then Throw("File '" + arg + "' does not exist")
  if extension <> null then do
    {drive, folder, name, ext} = SplitPath(arg)
    if ext <> "." + extension then Throw(
      "File '" + arg+ "' must have a '" + extension + "' extension."
    )
  end
  return(arg)
endmacro

/*
Checks that an argument is a vector or can be converted to one.

Inputs (in named array)
  * vector
    * The vector to be checked
  * required
    * True/False: if the argument is required (by the parent macro).

Returns
  * The vector
*/

Macro "check vector" (MacroOpts)

  arg = MacroOpts.vector
  required = MacroOpts.required

  if TypeOf(arg) = "null" then do
    if required
      then Throw("An argument is missing or not provided.")
      else return()
  end
  if TypeOf(arg) = "array" then arg = A2V(arg)
  if TypeOf(arg) <> "vector" then arg = A2V({arg})
  return(arg)
endmacro

/*doc
Checks that an argument is an array or can be converted to one.

Inputs (in named array)
  * array
    * The array to be checked
  * required
    * True/False: if the argument is required (by the parent macro).

Returns
  * The array
*/

Macro "check array" (MacroOpts)

  arg = MacroOpts.array
  required = MacroOpts.required

  if TypeOf(arg) = "null" then do
    if required
      then Throw("An argument is missing or not provided.")
      else return()
  end
  if TypeOf(arg) = "vector" then arg = V2A(arg)
  if TypeOf(arg) <> "array" then arg = {arg}
  return(arg)
endmacro

/*
Checks that an argument is a string

Inputs (in named array)
  * string
    * The string to be checked
  * required
    * True/False: if the argument is required (by the parent macro).
*/

Macro "check string" (MacroOpts)

  arg = MacroOpts.string
  required = MacroOpts.required

  if TypeOf(arg) = "null" then do
    if required
      then Throw("An argument is missing or not provided.")
      else return()
  end
  if TypeOf(arg) <> "string" then Throw(
    "Expected string but found " + TypeOf(arg)
  )
  return(arg)
endmacro

/*
Macro to simplify the process of map creation.

Inputs
  MacroOpts
    Named array that holds argument names

    file
      String
      Full path to the file to map. Supported types:
        Point, Line, Polygon geographic files. RTS files.

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
  map_name = RunMacro("Get Unique Map Name")

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
    map_name = "gisdk_tools1"
  end else do
    num = 0
    exists = "True"
    while exists do
      num = num + 1
      map_name = "gisdk_tools" + String(num)
      exists = if (ArrayPosition(map_names, {map_name}, ) <> 0)
        then "True"
        else "False"
    end
  end

  return(map_name)
EndMacro
