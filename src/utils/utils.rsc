/*
Closes any views and maps. Does not call "G30 File Close All", because that
would close the flowchart.
*/

Macro "Close All" (scen_dir)

  // Close maps
  maps = GetMapNames()
  if maps <> null then do
    for map in maps do
      CloseMap(map)
    end
  end

  {views, , } = GetViews()
  if views <> null then do
    for view in views do
      CloseView(view)
    end
  end
endMacro

/*
Removes any progress bars open
*/

Macro "Destroy Progress Bars"
  on notfound goto quit
  while 0 < 1 do
    DestroyProgressBar()
  end
  quit:
  on notfound default
EndMacro

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

    // Get the RTS's roadway file
    opts = null
    opts.rts_file = file
    hwy_dbd = RunMacro("Get RTS Roadway File", opts)
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

/*
Uses the batch shell to copy the folders and subfolders from
one directory to another.

Inputs (all in a named array)
  * from
    * String
    * Full path of directory to copy
  * to
    * String
    * Full path of destination
  * copy_files
    * Optional true/false
    * Whether or not to copy files
    * Defaults to true
  * subdirectories
    * Optional true/false
    * Whether or not to include subdirectories
    * Defaults to true
  * purge
   * Optional true/false
   * Whether to delete files in `to` that are no longer present in `from`
   * Defaults to true
*/

Macro "Copy Directory" (MacroOpts)

  from = MacroOpts.from
  to = MacroOpts.to
  copy_files = MacroOpts.copy_files
  subdirectories = MacroOpts.subdirectories
  purge = MacroOpts.purge

  if from = null then Throw("Copy Diretory: 'from' not provided") 
  if to = null then Throw("Copy Diretory: 'from' not provided") 
  if copy_files = null then copy_files = "true"
  if subdirectories = null then subdirectories = "true"
  if purge = null then purge = "true"

  RunMacro("Normalize Path", from)
  RunMacro("Normalize Path", to)

  from = "\"" +  from + "\""
  to = "\"" +  to + "\""
  cmd = "cmd /C robocopy " + from + " " + to
  if !copy_files then cmd = cmd + " /t"
  if subdirectories then cmd = cmd + " /e"
  if purge then cmd = cmd + " /purge"
  opts.Minimize = "true"
  RunProgram(cmd, opts)
EndMacro

/*
Takes a path like this:
C:\\projects\\model\\..\\other_model

and turns it into this:
C:\\projects\\other_model

Works whether using "\\" or "/" for directory markers

Also removes any trailing slashes
*/

Macro "Normalize Path" (rel_path)

  a_parts = ParseString(rel_path, "/\\")
  for i = 1 to a_parts.length do
    part = a_parts[i]

    if part <> ".." then do
      a_path = a_path + {part}
    end else do
      a_path = ExcludeArrayElements(a_path, a_path.length, 1)
    end
  end

  for i = 1 to a_path.length do
    if i = 1
      then path = a_path[i]
      else path = path + "\\" + a_path[i]
  end

  return(path)
EndMacro

/*
Takes a query string and makes sure it is of the form:
"Select * where ...""

Inputs
  query
    String
    A query. Can be "Select * where ID = 1" or just the "ID = 1"

Returns
  A query of the form "Select * where ..."
*/

Macro "Normalize Query" (query)

  if query = null then Throw("Normalize Query: 'query' not provided")

  if Left(query, 15) = "Select * where "
    then return(query)
    else return("Select * where " + query)
EndMacro

/*
Simple improvement on CreateDirectory(). This only creates a directory if it
doesn't already exist. It does not throw an error like CreateDirectory(). It
also normalizes the path of `dir` (resolves relative paths and removes any
trailing slashes).

Inputs
  * dir
    * String
    * Path of directory to create.
*/

Macro "Create Directory" (dir)
  if dir = null then Throw("Create Directory: 'dir' not provided") 
  dir = RunMacro("Normalize Path", dir)
  if GetDirectoryInfo(dir, "All") = null then CreateDirectory(dir)
EndMacro

/*
Recursively searches the directory and any subdirectories for files.
This can be useful for cataloging all the files created by the model.

Inputs:
dir
  String
  The directory to search

ext
  Optional string or array of strings
  extensions to limit the search to.
  e.g. "rsc" or {"rsc", "lst", "bin"}
  If null, finds files of all types.

Output:
An array of complete paths for each file found
*/

Macro "Catalog Files" (dir, ext)

  if TypeOf(ext) = "string" then ext = {ext}

  a_dirInfo = GetDirectoryInfo(dir + "/*", "Directory")

  // If there are folders in the current directory,
  // call the macro again for each one.
  if a_dirInfo <> null then do
    for d = 1 to a_dirInfo.length do
      path = dir + "/" + a_dirInfo[d][1]

      a_files = a_files + RunMacro("Catalog Files", path, ext)
    end
  end

  // If the ext parameter is used
  if ext <> null then do
    for e = 1 to ext.length do
      if Left(ext[e], 1) = "." 
        then path = dir + "/*" + ext[e]
        else path = dir + "/*." + ext[e]

      a_info = GetDirectoryInfo(path, "File")
      if a_info <> null then do
        for i = 1 to a_info.length do
          a_files = a_files + {dir + "/" + a_info[i][1]}
        end
      end
    end
  // If the ext parameter is not used
  end else do
    a_info = GetDirectoryInfo(dir + "/*", "File")
    if a_info <> null then do
      for i = 1 to a_info.length do
        a_files = a_files + {dir + "/" + a_info[i][1]}
      end
    end
  end

  return(a_files)
EndMacro

/*
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
    * If "false", functions the same as GetFields()
  
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

    array_name = if Left(name, 1) = "[" and Right(name, 1) = "]"
      then Substring(name, 2, StringLength(name) - 2)
      else name
    
    name_result.(array_name) = name
    spec_result.(array_name) = spec
  end
  return({name_result, spec_result})
endmacro

/*
Makes a copy of all the files comprising a route system.
Optionally includes the roadway dbd.

Inputs

  MacroOpts
    Named array containing all argument macros

    from_rts
      String
      Full path to the route system to copy. Ends in ".rts"

    to_dir
      String
      Full path to the directory where files will be copied

    include_hwy_files
      Optional True/False
      Whether to also copy the roadway files. Defaults to false. Because of the
      fragile nature of the RTS file, the roadway layer is first assumed to be
      in the same folder as the RTS file. If it isn't, GetRouteSystemInfo() will
      be used to try and locate it; however, this method is prone to errors if
      the route system is in different places on different machines. As a general
      rule, always keep the roadway layer and the RTS layer together.

Returns
  rts_file
    String
    Full path to the resulting .RTS file
*/

Macro "Copy RTS Files" (MacroOpts)

  // Argument extraction
  from_rts = MacroOpts.from_rts
  to_dir = MacroOpts.to_dir
  include_hwy_files = MacroOpts.include_hwy_files

  // Argument check
  if from_rts = null then Throw("Copy RTS Files: 'from_rts' not provided")
  if to_dir = null then Throw("Copy RTS Files: 'to_dir' not provided")
  to_dir = RunMacro("Normalize Path", to_dir)

  // Get the directory containing from_rts
  a_rts_path = SplitPath(from_rts)
  from_dir = RunMacro("Normalize Path", a_rts_path[1] + a_rts_path[2])
  to_rts = to_dir + "/" + a_rts_path[3] + a_rts_path[4]

  // Create to_dir if it doesn't exist
  if GetDirectoryInfo(to_dir, "All") = null then CreateDirectory(to_dir)

  // Get all files comprising the route system
  {a_names, a_sizes} = GetRouteSystemFiles(from_rts)
  for file_name in a_names do
    from_file = from_dir + "/" + file_name
    to_file = to_dir + "/" + file_name
    CopyFile(from_file, to_file)
  end

  // If also copying the roadway files
  if include_hwy_files then do

    // Get the roadway file. Use gisdk_tools macro to avoid common errors
    // with GetRouteSystemInfo()
    opts = null
    opts.rts_file = from_rts
    from_hwy_dbd = RunMacro("Get RTS Roadway File", opts)

    // Use the to_dir to create the path to copy to
    a_path = SplitPath(from_hwy_dbd)
    to_hwy_dbd = to_dir + "/" + a_path[3] + a_path[4]

    CopyDatabase(from_hwy_dbd, to_hwy_dbd)

    // Change the to_rts to point to the to_hwy_dbd
    {nlyr, llyr} = GetDBLayers(to_hwy_dbd)
    ModifyRouteSystem(
      to_rts,{
        {"Geography", to_hwy_dbd, llyr},
        {"Link ID", "ID"}
      }
    )

    // Return both resulting RTS and DBD
    return({to_rts, to_hwy_dbd})
  end

  // Return the resulting RTS file
  return(to_rts)
EndMacro

/*
GetRouteSystemInfo() can sometimes return roadway file paths that are incorrect.
This macro assumes that the roadway dbd is in the same folder as the rts file.
If no file is present there, then it checks the file listed in the rts info.

Inputs (all in named array)
  * rts_file
    * String
    * Full path to the RTS file whose roadway file you want to locate.

Returns
  * String - full path to the roadway file associated with the RTS.
*/

Macro "Get RTS Roadway File" (MacroOpts)

  // Argument extraction
  rts_file = MacroOpts.rts_file

  // Argument checking
  if rts_file = null then Throw("Get RTS Roadway File: 'rts_file' not provided")

  // Get the hwy_dbd from the route system file. This is often wrong/buggy even
  // if the RTS opens the correct line layer when opening manually in TransCAD.
  a_rts_info = GetRouteSystemInfo(rts_file)
  hwy_dbd1 = a_rts_info[1]

  // First, assume that the roadway dbd is in the same folder as the RTS.
  a_path = SplitPath(hwy_dbd1)
  a_rts_path = SplitPath(rts_file)
  hwy_dbd = a_rts_path[1] + a_rts_path[2] + a_path[3] + a_path[4]
  
  // If the right roadway file exists in the directory but the route system
  // is pointing elsewhere, fix it.
  if GetFileInfo(hwy_dbd) <> null and hwy_dbd <> hwy_dbd1 then do
    {nlyr, llyr} = GetDBLayers(hwy_dbd)
    ModifyRouteSystem(rts_file, {{"Geography", hwy_dbd, llyr}})
  end

  // If the roadway file does not exist in the same folder as the rts_file,
  // use the original path returned by GetRouteSystemInfo().
  if GetFileInfo(hwy_dbd) = null then hwy_dbd = hwy_dbd1

  // If there is no file at that path, throw an error message
  if GetFileInfo(hwy_dbd) = null
    then Throw(
      "Get RTS Roadway File: The roadway network associated with this RTS\n" +
      "cannot be found in the same directory as the RTS nor at: \n" +
      hwy_dbd1
    )

  return(hwy_dbd)
EndMacro

/*
This macro expands the base functionality of SelectNearestFeatures() to perform
a spatial join. Only works on point and area layers. Master and
slave layers must be open in the same (current) map.

Inputs
  MacroOpts
    Named array of macro arguments (e.g. MacroOpts.master_view)

    master_layer
      String
      Name of master layer (left side of table)

    master_set
      Optional string
      Name of selection set of features to be joined. If null, all features
      are joined.

    slave_layer
      String
      Name of the slave layer (right side of table)

    slave_set
      Optional string
      Name of selection set that slave features must be in to be joined.

    threshold
      Optional string
      Maximum distance to search around each feature in the slave layer.
      Defaults to 100 feet.


Returns
  The name of the joined view.
  Also modifies the master table by adding a slave ID field (this is how the
  join is accomplished).
*/

Macro "Spatial Join" (MacroOpts)

  // Argument extraction
  master_layer = MacroOpts.master_layer
  master_set = MacroOpts.master_set
  slave_layer = MacroOpts.slave_layer
  slave_set = MacroOpts.slave_set
  threshold = MacroOpts.threshold

  // Argument checking
  if master_layer = null then Throw("Spatial Join: 'master_layer' not provided")
  if slave_layer = null then Throw("Spatial Join: 'slave_layer' not provided")
  if threshold = null then do
    units = GetMapUnits("Plural")
    threshold = if units = "Miles" then 100 / 5280
      else if units = "Feet" then 100
    if threshold = null then Throw("Map units must be feet or miles")
  end

  // Add fields to the master_layer
  a_fields = {
    {"slave_id", "Integer", 10, ,,,,"used to join to slave layer"},
    {"slave_dist", "Real", 10, 3,,,,"used to join to slave layer"}
  }
  RunMacro("Add Fields", {view: master_layer, a_fields: a_fields})

  // Tag the master layer with slave IDs and distances
  TagLayer(
    "Value",
    master_layer + "|" + master_set,
    master_layer + ".slave_id",
    slave_layer + "|" + slave_set,
    slave_layer + ".ID"
  )
  TagLayer(
    "Distance",
    master_layer + "|" + master_set,
    master_layer + ".slave_dist",
    slave_layer + "|" + slave_set,
  )

  // Select records where the tagged distance is greater than the threshol and
  // remove those tagged IDs.
  SetLayer(master_layer)
  qry = "Select * where nz(slave_dist) > " + String(threshold)
  set = CreateSet("set")
  n = SelectByQuery(set, "several", qry)
  if n > 0 then do
    v = Vector(n, "Long", )
    SetDataVector(master_layer + "|" + set, "slave_id", v, )
  end
  DeleteSet(set)

  // Create a joined view based on the slave IDs
  jv = JoinViews("jv", master_layer + ".slave_id", slave_layer + ".ID", )

  SetView(jv)
  return(jv)
EndMacro

/*
Renames a field in a TC view

Inputs
  view_name
    String
    Name of view to modify

  current_name
    String
    Name of field to rename

  new_name
    String
    New name to use
*/

Macro "Rename Field" (view_name, current_name, new_name)

  // Argument Check
  if view_name = null then Throw("Rename Field: 'view_name' not provided")
  if current_name = null then Throw("Rename Field: 'current_name' not provided")
  if new_name = null then Throw("Rename Field: 'new_name' not provided")

  // Get and modify the field info array
  a_str = GetTableStructure(view_name)
  field_modified = "false"
  for s = 1 to a_str.length do
    a_field = a_str[s]
    field_name = a_field[1]

    // Add original field name to end of field array
    a_field = a_field + {field_name}

    // rename field if it's the current field
    if field_name = current_name then do
      a_field[1] = new_name
      field_modified = "true"
    end

    a_str[s] = a_field
  end

  // Modify the table
  ModifyTable(view_name, a_str)

  // Throw error if no field was modified
  if !field_modified
    then Throw(
      "Rename Field: Field '" + current_name +
      "' not found in view '" + view_name + "'"
    )
EndMacro

/*
Removes a field from a view/layer

Input
viewName  Name of view or layer (must be open)
field_name Name of the field to remove. Can pass string or array of strings.
*/

Macro "Remove Field" (viewName, field_name)
  a_str = GetTableStructure(viewName)

  if TypeOf(field_name) = "string" then field_name = {field_name}

  for fn = 1 to field_name.length do
    name = field_name[fn]

    for i = 1 to a_str.length do
      a_str[i] = a_str[i] + {a_str[i][1]}
      if a_str[i][1] = name then position = i
    end
    if position <> null then do
      a_str = ExcludeArrayElements(a_str, position, 1)
      ModifyTable(viewName, a_str)
    end
  end
EndMacro

/*
Creates a simple .net file using just the length attribute. Many processes
require a simple network.

Inputs (all in a named array)
    * llyr
      * String - provide either llyr or hwy_dbd (not both)
      * Name of line layer to create network from. If provided, the macro assumes
        the layer is already in the workspace. Either 'llyr' or 'hwy_dbd' must
        be provided.
    * hwy_dbd
      * String - provide either llyr or hwy_dbd (not both)
      * Full path to the roadway DBD file to create a network. If provided, the
        macro assumes that it is not already open in the workspace.Either 'llyr'
        or 'hwy_dbd' must be provided.
    * centroid_qry
      * Optional String
      * Query defining centroid set. If null, a centroid set will not be created.
        e.g. "FCLASS = 99"

Returns
  * net_file
    * String
    * Full path to the network file created by the network. Will be in the
      same directory as the hwy_dbd.
*/

Macro "Create Simple Roadway Net" (MacroOpts)

  RunMacro("TCB Init")

  // Argument extraction
  llyr = MacroOpts.llyr
  llyr_provided = if (llyr <> null) then "true" else "false"
  hwy_dbd = MacroOpts.hwy_dbd
  hwy_dbd_provided = if (hwy_dbd <> null) then "true" else "false"
  centroid_qry = MacroOpts.centroid_qry

  // Argument checking
  if !llyr_provided and !hwy_dbd_provided = null then Throw(
    "Either 'llyr' or 'hwy_dbd' must be provided."
  )
  if llyr_provided and hwy_dbd_provided then Throw(
    "Provide only 'llyr' or 'hwy_dbd'. Not both."
  )

  // If llyr is provided, get the hwy_dbd
  // Get info about hwy_dbd
  if llyr_provided then do
    map = GetMap()
    SetLayer(llyr)
    if map = null then Throw("Simple Network: 'llyr' must be in current map")
    a_layers = GetMapLayers(map, "Line")
    in_map = if (ArrayPosition(a_layers, {llyr}, ) = 0) then "false" else "true"
    if !in_map then Throw("Simple Network: 'llyr' must be in the current map")

    hwy_dbd = GetLayerDB(llyr)
    {nlyr, } = GetDBLayers(hwy_dbd)
  // if hwy_dbd is provided, open it in a map
  end else do
    {nlyr, llyr} = GetDBLayers(hwy_dbd)
    map = RunMacro("G30 new map", hwy_dbd)
  end
  a_path = SplitPath(hwy_dbd)
  out_dir = RunMacro("Normalize Path", a_path[1] + a_path[2])

  // Create a simple network of the scenario highway layer
  SetLayer(llyr)
  set_name = null
  net_file = out_dir + "/simple.net"
  label = "Simple Network"
  link_fields = {{"Length", {llyr + ".Length", llyr + ".Length", , , "False"}}}
  node_fields = null
  opts = null
  opts.[Time Units] = "Minutes"
  opts.[Length Units] = "Miles"
  opts.[Link ID] = llyr + ".ID"
  opts.[Node ID] = nlyr + ".ID"
  opts.[Turn Penalties] = "Yes"
  nh = CreateNetwork(set_name, net_file, label, link_fields, node_fields, opts)

  // Add centroids to the network to prevent routes from passing through
  // Network Settings
  if centroid_qry <> null then do

    centroid_qry = RunMacro("Normalize Query", centroid_qry)

    opts = null
    opts.Input.Database = hwy_dbd
    opts.Input.Network = net_file
    opts.Input.[Centroids Set] = {
      hwy_dbd + "|" + nlyr, nlyr,
      "centroids", centroid_qry
    }
    ok = RunMacro("TCB Run Operation", "Highway Network Setting", opts, &Ret)
    if !ok then Throw(
      "Simple Network: Setting centroids failed"
    )
  end

  // Workspace clean up.
  // If this macro create the map, then close it.
  if hwy_dbd_provided then CloseMap(map)

  return(net_file)
EndMacro

/*
table   String Can be a file path or view of the table to modify
field   Array or string
string  Array or string
*/

Macro "Add Field Description" (table, field, description)

  if table = null or field = null or description = null then Throw(
    "Missing arguments to 'Add Field Description'"
    )
  if TypeOf(field) = "string" then field = {field}
  if TypeOf(description) = "string" then description = {description}
  if field.length <> description.length then Throw(
    "The same number of fields and descriptions must be provided."
  )
  isView = RunMacro("Is View", table)

  // If the table variable is not a view, then attempt to open it
  if isView = "no" then table = OpenTable("table", "FFB", {table})

  str = GetTableStructure(table)
  for f = 1 to str.length do
    str[f] = str[f] + {str[f][1]}
    name = str[f][1]

    pos = ArrayPosition(field, {name}, )
    if pos <> 0 then str[f][8] = description[pos]
  end
  ModifyTable(table, str)

  // If this macro opened the table, close it
  if isView = "no" then CloseView(table)
EndMacro

/*
Tests whether or not a string is a view name or not
*/

Macro "Is View" (string)

  a_views = GetViewNames()
  if ArrayPosition(a_views, {string}, ) = 0 then return("false")
  else return("true")
EndMacro

/*
Checks to see if a variable is a named array. (e.g.: {{"name"}, {value}})
*/

Macro "Is Named Array" (var)
  if TypeOf(var) <> "array"  then return("false")
  if TypeOf(var[1]) <> "array"  then return("false")
  if var[1].length <> 2  then return("false")
  if TypeOf(var[1][1]) <> "string" then return("false")
  return("true")
EndMacro

/*
Converts anything passed in to an array.
*/

Macro "2A" (thing)
  if TypeOf(thing) = "array" then return(thing)
  thing = if TypeOf(thing) = "vector" then V2A(thing) else {thing}
  return(thing)
EndMacro

/*
Converts anything passed in to a string. If an array of things is passed in,
an array of strings is returned.
*/

Macro "2S" (thing)
  type = TypeOf(thing)
  if type = "string" then return(thing)
  if type = "vector" or type = "array" then do
    for i = 1 to thing.length do
      thing[i] = RunMacro("2S", thing[i])
    end
  end else thing = String(thing)
  return(thing)
EndMacro

/*

*/

Macro "Create Sum Product Fields" (MacroOpts)

  view = MacroOpts.view
  factor_file = MacroOpts.factor_file

  if factor_file = null then Throw("'factor_file' not provided")

  fac_vw = OpenTable("factors", "CSV", {factor_file})
  {names, } = GetFields(fac_vw, "All")

  input_fields = GetDataVector(fac_vw + "|", names[1], )
  input = GetDataVectors(view + "|", V2A(input_fields), {OptArray: true})
  // Remove first and last column (Field and Description)
  output_fields = ExcludeArrayElements(names, 1, 1)
  output_fields = ExcludeArrayElements(output_fields, output_fields.length, 1)

  for output_field in output_fields do
    a_fields = a_fields + {{output_field, "Real", 10, 2, , , , }}
    output.(output_field) = Vector(input[1][2].length, "Real", {Constant: 0})
    factors = nz(GetDataVector(fac_vw + "|", output_field, ))
    
    for i = 1 to input_fields.length do
      input_field = input_fields[i]
      factor = factors[i]

      output.(output_field) = output.(output_field) + nz(input.(input_field)) * factor
    end
  end
  RunMacro("Add Fields", {view: view, a_fields: a_fields, initial_values: 0})
  SetDataVectors(view + "|", output, )

  CloseView(fac_vw)
endmacro

/*
An alternative to to the JoinTableToLayer() GISDK function, which replaces
the existing bin file with a new one (losing original fields).
This version allows you to permanently append new fields while keeping the old.

Inputs
  * masterFile
    * String
    * Full path of master geographic or binary file
  * mID
    * String
    * Name of master field to use for join.
  * slaveFile
    * String
    * Full path of slave table.  Can be FFB or CSV.
  * sID
    * String
    * Name of slave field to use for join.
  * overwrite
    * Boolean
    * Whether or not to replace any existing
    * fields with joined values.  Defaults to true.
    * If false, the fields will be added with ":1".

Returns
Nothing. Permanently appends the slave data to the master table.

Example application
- Loading assignment results to a link layer
- Attaching an SE data table to a TAZ layer
*/

Macro "Join Table To Layer" (masterFile, mID, slaveFile, sID, overwrite)

  if overwrite = null then overwrite = "True"

  // Determine master file type
  path = SplitPath(masterFile)
  if path[4] = ".dbd" then type = "dbd"
  else if path[4] = ".bin" then type = "bin"
  else Throw("Master file must be .dbd or .bin")

  // Open the master file
  if type = "dbd" then do
    {nlyr, master} = GetDBLayers(masterFile)
    master = AddLayerToWorkspace(master, masterFile, master)
    nlyr = AddLayerToWorkspace(nlyr, masterFile, nlyr)
  end else do
    masterDCB = Substitute(masterFile, ".bin", ".DCB", )
    master = OpenTable("master", "FFB", {masterFile, })
  end

  // Determine slave table type and open
  path = SplitPath(slaveFile)
  if path[4] = ".csv" then s_type = "CSV"
  else if path[4] = ".bin" then s_type = "FFB"
  else Throw("Slave file must be .bin or .csv")
  slave = OpenTable("slave", s_type, {slaveFile, })

  // If mID is the same as sID, rename sID
  if mID = sID then do
    // Can only modify FFB tables.  If CSV, must convert.
    if s_type = "CSV" then do
      tempBIN = GetTempFileName("*.bin")
      ExportView(slave + "|", "FFB", tempBIN, , )
      CloseView(slave)
      slave = OpenTable("slave", "FFB", {tempBIN, })
    end

    str = GetTableStructure(slave)
    for s = 1 to str.length do
      str[s] = str[s] + {str[s][1]}

      str[s][1] = if str[s][1] = sID then "slave" + sID
        else str[s][1]
    end
    ModifyTable(slave, str)
    sID = "slave" + sID
  end

  // Remove existing fields from master if overwriting
  if overwrite then do
    {a_mFields, } = GetFields(master, "All")
    {a_sFields, } = GetFields(slave, "All")

    for f = 1 to a_sFields.length do
      field = a_sFields[f]
      if field <> sID & ArrayPosition(a_mFields, {field}, ) <> 0
        then RunMacro("Remove Field", master, field)
    end
  end

  // Join master and slave. Export to a temporary binary file.
  jv = JoinViews("perma jv", master + "." + mID, slave + "." + sID, )
  SetView(jv)
  a_path = SplitPath(masterFile)
  tempBIN = a_path[1] + a_path[2] + "temp.bin"
  tempDCB = a_path[1] + a_path[2] + "temp.DCB"
  ExportView(jv + "|", "FFB", tempBIN, , )
  CloseView(jv)
  CloseView(master)
  CloseView(slave)

  // Swap files.  Master DBD files require a different approach
  // from bin files, as the links between the various database
  // files are more complicated.
  if type = "dbd" then do
    // Join the tempBIN to the DBD. Remove Length/Dir fields which
    // get duplicated by the DBD.
    opts = null
    opts.Ordinal = "True"
    JoinTableToLayer(masterFile, master, "FFB", tempBIN, tempDCB, mID, opts)
    master = AddLayerToWorkspace(master, masterFile, master)
    nlyr = AddLayerToWorkspace(nlyr, masterFile, nlyr)
    RunMacro("Remove Field", master, "Length:1")
    RunMacro("Remove Field", master, "Dir:1")

    // Re-export the table to clean up the bin file
    new_dbd = a_path[1] + a_path[2] + a_path[3] + "_temp" + a_path[4]
    {l_names, l_specs} = GetFields(master, "All")
    {n_names, n_specs} = GetFields(nlyr, "All")
    opts = null
    opts.[Field Spec] = l_specs
    opts.[Node Name] = nlyr
    opts.[Node Field Spec] = n_specs
    ExportGeography(master + "|", new_dbd, opts)
    DropLayerFromWorkspace(master)
    DropLayerFromWorkspace(nlyr)
    DeleteDatabase(masterFile)
    CopyDatabase(new_dbd, masterFile)
    DeleteDatabase(new_dbd)

    // Remove the sID field
    master = AddLayerToWorkspace(master, masterFile, master)
    RunMacro("Remove Field", master, sID)
    DropLayerFromWorkspace(master)

    // Delete the temp binary files
    DeleteFile(tempBIN)
    DeleteFile(tempDCB)
  end else do
    // Remove the master bin files and rename the temp bin files
    DeleteFile(masterFile)
    DeleteFile(masterDCB)
    RenameFile(tempBIN, masterFile)
    RenameFile(tempDCB, masterDCB)

    // Remove the sID field
    view = OpenTable("view", "FFB", {masterFile})
    RunMacro("Remove Field", view, sID)
    CloseView(view)
  end
EndMacro

/*
For base model calibration, maps comparing model and count volumes are required.
This macro creates a standard map to show absolute and percent differences in a
color theme. It also performs maximum desirable deviation calculations and
highlights (in green) links that do not exceed the MDD.

Inputs
  macro_opts
    Named array of macro arguments

    output_file
      String
      Complete path of the output map to create.

    hwy_dbd
      String
      Complete path to the highway geographic file.

    count_id_field
      String
      Field name of the count ID. The count ID field is used to determine
      where a single count has been split between multiple links (like on a
      freeway).

    combine_oneway_pairs
      Optional true/false
      Defaults to true
      Whether or not to combine one-way pair counts and volumes before
      calculating stats.

    count_field
      String
      Name of the field containing the count volume. Can be a daily or period
      count field, but time period between count and volume fields should
      match.

    vol_field
      String
      Name of the field containing the model volume. Can be a daily or period
      count field, but time period between count and volume fields should
      match.

    field_suffix
      Optional string
      "" by default. If provided, will be appended to the fields created by this
      macro. For example, if making a count difference map of SUT vs SUT counts,
      you could provide a suffix of "SUT". This would lead to fields created
      like "Count_SUT", "Volume_SUT", "diff_SUT", etc. This is used to prevent
      repeated calls to this macro from overwriting these fields.



Depends
  gplyr
*/

Macro "Count Difference Map" (macro_opts)

  output_file = macro_opts.output_file
  hwy_dbd = macro_opts.hwy_dbd
  count_id_field = macro_opts.count_id_field
  combine_oneway_pairs = macro_opts.combine_oneway_pairs
  count_field = macro_opts.count_field
  vol_field = macro_opts.vol_field
  field_suffix = macro_opts.field_suffix

  if combine_oneway_pairs = null then combine_oneway_pairs = "true"

  // set the field suffix
  if field_suffix = null then field_suffix = ""
  if field_suffix <> "" then do
    if field_suffix[1] <> "_" then field_suffix = "_" + field_suffix
  end

  // Determine output directory (removing trailing backslash)
  a_path = SplitPath(output_file)
  output_dir = a_path[1] + a_path[2]
  len = StringLength(output_dir)
  output_dir = Left(output_dir, len - 1)

  // Create output directory if it doesn't exist
  if GetDirectoryInfo(output_dir, "All") = null then CreateDirectory(output_dir)

  // Create map
  {map, {nlyr, vw}} = RunMacro("Create Map", {file: hwy_dbd})
  SetLayer(vw)

  // Add fields for mapping
  a_fields = {
    {"NumCountLinks","Integer",8,,,,, "Number of links with this count ID"},
    {"Count","Integer",8,,,,, "Repeat of the count field"},
    {"Volume","Real",8,,,,, "Total Daily Link Flow"},
    {"diff","Integer",8,,,,, "Volume - Count"},
    {"absdiff","Integer",8,,,,, "abs(diff)"},
    {"pctdiff","Integer",8,,,,, "diff / Count * 100"},
    {"MDD","Integer",8,,,,, "Maximum Desirable Deviation"},
    {"ExceedMDD","Integer",8,,,,, "If link exceeds MDD"}
  }
  // RunMacro("TCB Add View Fields", {vw, a_fields})
  RunMacro("Add Fields", {view: vw, a_fields: a_fields})

  // Create data frame
  df = CreateObject("df")
  opts = null
  opts.view = vw
  opts.fields = {count_id_field, count_field, vol_field}
  df.read_view(opts)
  df.rename(count_field, "Count")
  df.rename(vol_field, "Volume")

  if combine_oneway_pairs then do
    // Aggregate by count ID
    df2 = df.copy()
    df2.group_by(count_id_field)
    df2.summarize({"Count", "Volume"}, "sum")
    df2.filter(count_id_field + " <> null")
    df2.rename("Count", "NumCountLinks")

    // Join aggregated data back to disaggregate column of count IDs
    df.select(count_id_field)
    df.left_join(df2, count_id_field, count_id_field)
    df.rename("sum_Count", "Count")
    df.rename("sum_Volume", "Volume")
  end else do
    df.select({count_id_field, "Count", "Volume"})
  end

  // Calculate remaining fields
  df.mutate("diff", df.tbl.Volume - df.tbl.Count)
  df.mutate("absdiff", abs(df.tbl.diff))
  df.mutate("pctdiff", df.tbl.diff / df.tbl.Count * 100)
  v_c = df.tbl.Count
  v_MDD = if (v_c <= 50000) then (11.65 * Pow(v_c, -.37752)) * 100
     else if (v_c <= 90000) then (400 * Pow(v_c, -.7)) * 100
     else if (v_c <> null)  then (.157 - v_c * .0000002) * 100
     else null
  df.mutate("MDD", v_MDD)
  v_exceedMDD = if abs(df.tbl.pctdiff) > v_MDD then 1 else 0
  df.mutate("ExceedMDD", v_exceedMDD)

  // Fill data view
  df.update_view(vw)

  // Rename fields to add suffix (and remove any that already exist)
  for f = 1 to a_fields.length do
    cur_field = a_fields[f][1]

    new_field = cur_field + field_suffix
    RunMacro("Remove Field", vw, new_field)
    RunMacro("Rename Field", vw, cur_field, new_field)
  end

  // Scaled Symbol Theme
  SetLayer(vw)
  flds = {vw + ".absdiff" + field_suffix}
  opts = null
  opts.Title = "Absolute Difference"
  opts.[Data Source] = "All"
  opts.[Minimum Value] = 0
  opts.[Maximum Value] = 50000
  opts.[Minimum Size] = .25
  opts.[Maximum Size] = 12
  theme_name = CreateContinuousTheme("Flows", flds, opts)

  // Set color to white to make it disappear in legend
  dual_colors = {ColorRGB(65535,65535,65535)}
  // without black outlines
  dual_linestyles = {LineStyle({{{1, -1, 0}}})}
  // with black outlines
  /*dual_linestyles = {LineStyle({{{2, -1, 0},{0,0,1},{0,0,-1}}})}*/
  dual_linesizes = {0}
  SetThemeLineStyles(theme_name , dual_linestyles)
  SetThemeLineColors(theme_name , dual_colors)
  SetThemeLineWidths(theme_name , dual_linesizes)

  ShowTheme(, theme_name)

  // Apply the color theme breaks
  cTheme = CreateTheme(
    "Count % Difference", vw+".pctdiff" + field_suffix, "Manual", 8,{
      {"Values",{
        {-100, "True", -50, "False"},
        {-50, "True", -30, "False"},
        {-30, "True", -10, "False"},
        {-10, "True", 10, "True"},
        {10, "False", 30, "True"},
        {30, "False", 50, "True"},
        {50, "False", 100, "True"},
        {100, "False", 10000, "True"}
        }},
      {"Other", "False"}
    }
  )

  // Set color theme line styles and colors
  line_colors =	{
    ColorRGB(17733,30069,46260),
    ColorRGB(29812,44461,53713),
    ColorRGB(43947,55769,59881),
    ColorRGB(0,0,0),
    ColorRGB(65278,57568,37008),
    ColorRGB(65021,44718,24929),
    ColorRGB(62708,28013,17219),
    ColorRGB(55255,12336,10023)
  }
  solidline = LineStyle({{{1, -1, 0}}})
  // This one puts black borders around the line
  /*dualline = LineStyle({{{2, -1, 0},{0,0,1},{0,0,-1}}})*/

  for i = 1 to 8 do
    class_id = GetLayer() +"|" + cTheme + "|" + String(i)
    SetLineStyle(class_id, dualline)
    SetLineColor(class_id, line_colors[i])
    SetLineWidth(class_id, 2)
  end

  // Change the labels of the classes (how the divisions appear in the legend)
  labels = {
    "-100 to -50", "-50 to -30", "-30 to -10",
    "-10 to 10", "10 to 30", "30 to 50",
    "50 to 100", ">100"
  }
  SetThemeClassLabels(cTheme, labels)

  ShowTheme(,cTheme)

  // Create a selection set of the links that do not exceed the MDD
  setname = "Deviation does not exceed MDD"
  RunMacro("G30 create set", setname)
  SelectByQuery(
    setname, "Several",
    "Select * where nz(Count" + field_suffix +
    ") > 0 and ExceedMDD" + field_suffix + " = 0"
  )
  SetLineColor(vw + "|" + setname, ColorRGB(11308, 41634, 24415))

  // Configure Legend
  RunMacro("G30 create legend", "Theme")
  SetLegendSettings (
    GetMap(),
    {
      "Automatic",
      {0, 1, 0, 1, 1, 4, 0},
      {1, 1, 1},
      {"Arial|Bold|16", "Arial|9", "Arial|Bold|16", "Arial|12"},
      {"", vol_field + " vs " + count_field}
    }
  )
  str1 = "XXXXXXXX"
  solid = FillStyle({str1, str1, str1, str1, str1, str1, str1, str1})
  SetLegendOptions (GetMap(), {{"Background Style", solid}})

  SetLayerVisibility(map + "|" + nlyr, "false")

  // Save map
  RedrawMap(map)
  RestoreWindow(GetWindowName())
  SaveMap(map, output_file)
  CloseMap(map)
EndMacro

/*
Uses the mode table to get the transit modes in the model. Exclude "nt"
(non-transit) as a mode.
*/

Macro "Get Transit Modes" (mode_csv)
    mode_vw = OpenTable("mode", "CSV", {mode_csv})
    transit_modes = V2A(GetDataVector(mode_vw + "|", "abbr", ))
    pos = transit_modes.position("nt")
    transit_modes = ExcludeArrayElements(transit_modes, pos, 1)
    CloseView(mode_vw)
    return(transit_modes)
endmacro

/*
Transposes all cores in a matrix file.

Inputs
  * `mtx_file`
    * String
    * Full path to matrix file to be transposed
  * `label`
    * Optional string
    * Label for the resuling, transposed matrix
    
Returns
  Nothing. The matrix file provided will have all cores transposed.
*/

Macro "Transpose Matrix" (mtx_file, label)
  if mtx_file = null then Throw("Transpose Matrix: `mtx_file` not provided")
  if GetFileInfo(mtx_file) = null then Throw(
    "Transpose Matrix: `mtx_file` not found\n" +
    "(" + mtx_file + ")"
  )

  {drive, folder, file, ext} = SplitPath(mtx_file)
  inv_matrix = drive + folder + file + "_inv" + ext
  mtx = OpenMatrix(mtx_file, )
  opts = null
  opts.[File Name] = inv_matrix
  opts.label = label
  TransposeMatrix(mtx, opts)
  mtx = null
  DeleteFile(mtx_file)
  RenameFile(inv_matrix, mtx_file)
EndMacro