/*
Creates a new class of object called a data_frame. Allows tables and other data
to be loaded into memory and manipulated more easily than a standard TC view.
Designed to mimic components of R packages `dplyr` and `tidyr`.

Inputs
  * tbl
    * Optional named array or string
    * Loads table data upon creation. If null, the data frame is created empty.
      If a string, must be a CSV or BIN file path. See the example below for a
      named array.
  * desc
    * Optional named array
    * Provides descriptions for each column in the data frame. Names must match
      column names in tbl.
    * The descriptions will only be visible if written to a bin file.
  * groups
    * Optional array of strings
    * Lists the grouping fields.
    * Set with `group_by()`

Create an empty data_frame by calling  

`df = CreateObject("df")`

Create a data frame with a starting table by passing a named array

```
tbl.a = {1, 2, 3}
tbl.b = {"a", "b", "c"}
desc.a = "This is a column of numbers."
desc.b = "This is a column of letters."
df = CreateObject("df", tbl, desc)
df.view()
```

| a | b |
|---|---|
| 1 | a |
| 2 | b |
| 3 | c |

*/

Class "df" (tbl, desc, groups)

  init do
    self.check_software()
    if tbl <> null then do
      tbl_type = TypeOf(tbl)
      if tbl_type = "string" then do
        if RunMacro("Is View", tbl) then do
          opts.view = tbl
          {class, spec} = GetViewTableInfo(tbl)
          if class = null then opts.include_descriptions = "false"
          else if !self.in(class, {"FFB", "RDM", "CDF"}) then opts.include_descriptions = "false"
          else opts.include_descriptions = "true"
          self.read_view(opts)
        end else do
          {drive, folder, name, ext} = SplitPath(tbl)
          if ext = ".csv" then self.read_csv(tbl)
          else if ext = ".bin" then self.read_bin(tbl)
          else Throw("df creation: only CSV and BIN files are supported")
        end
      end else self.tbl = CopyArray(tbl)
    end else self.tbl = CopyArray(tbl)
    self.desc = CopyArray(desc)
    self.groups = CopyArray(groups)
    self.check()
  EndItem

  /*doc
  Sets the description of a single field. 
  
  Inputs
    * `field`
      * String
      * Name of field whose description is to be set
    * `decsription`
      * String
      * The description to set
  
  Example:  
  `df.set_desc("a", "This is a field of numbers.")`
  
  Can also use:  
  `df.desc.(field) = description`
  */

  Macro "set_desc" (field, description) do
    if field = null then Throw("set_desc: 'field' not provided")
    if description = null then Throw("set_desc: 'description' not provided")
    self.desc.(field) = description
  EndItem
  
  /*doc
  Gets the description of a single field. 
  
  Inputs
    * `field`
      * String
      * Name of field to get description for

  Example:  
  `df.get_desc("a")`
  
  Can also use:
  `df.desc.(field)`
  */
  Macro "get_desc" (field) do
    if field = null then Throw("get_desc: 'field' not provided")
    return(self.desc.(field))
  EndItem

  /*doc
  Establishes grouping fields for the data frame.  This modifies the
  behavior of `summarize()`.
  
  Inputs
    * `fields`
      * Array of strings
      * Field names to add as grouping variables.
  */

  Macro "group_by" (fields) do

    // Argument checking and type handling
    if fields = null then Throw("group_by: no fields provided")
    if TypeOf(fields) = "string" then fields = {fields}

    self.groups = fields
  EndItem

  /*doc
  Removes any grouping attributes from the data frame
  */

  Macro "ungroup" do
    self.groups = null
  EndItem

  /*dontdoc
  Tests to see if the data frame is empty.  Usually called to stop other methods.
  */

  Macro "is_empty" do
    if self.tbl = null then return("true")
    if self.tbl.length = 1 and self.tbl[1] = null then return("true")
    return("false")
  EndItem

  /*doc
  This creates a complete copy of the data frame.  If you try

  `new_df = old_df`

  you simply get two variable names that point to the same object.
  Instead, use

  `new_df = old_df.copy()`
  */

  Macro "copy" do

    new_df = CreateObject("df")
    a_properties = GetObjectVariableNames(self)
    for p = 1 to a_properties.length do
      prop = a_properties[p]

      type = TypeOf(self.(prop))
      new_df.(prop) =
        if type = "array" then CopyArray(self.(prop))
        else if type = "vector" then CopyVector(self.(prop))
        else self.(prop)
    end

    return(new_df)
  EndItem

  /*doc
  Either returns vector of all column names or sets all column names. Use rename()
  to change individual column names.

  Inputs (all in named array)
      * `new_names`
        * Optional array or vector of strings
        * If provided, the method will set the column names to new_names instead
          of retrieve them
      * `start`
        * Optional string
        * Name of first column you want returned
        * Defaults to first column
      * `stop`
        * Optional string
        * Name of last column you want returned
        * Defaults to last column
  
  Returns
    By default, returns an array of column names.
  */
  
  Macro "colnames" (MacroOpts) do

    // Argument extraction
    new_names = MacroOpts.new_names
    start = MacroOpts.start
    stop = MacroOpts.stop

    // Argument checking
    if self.is_empty() then return()
    type = TypeOf(new_names)
    if type <> "null" then do
      if type = "vector" then new_names = V2A(new_names)
      else if type <> "array" then
        Throw("colnames: if provided, 'new_names' argument must be a vector or array")
      if new_names.length <> self.ncol() and start = null and stop = null then
        Throw("colnames: 'new_names' length does not match number of columns")
    end
    ok = "false"
    if start <> null then do
      for c = 1 to self.ncol() do
        col_name = self.tbl[c][1]
        if start = col_name then ok = "true"
      end
      if !ok then Throw("colnames:\n'" + start + "' not found in table")
    end
    ok = "false"
    if stop <> null then do
      for c = 1 to self.ncol() do
        col_name = self.tbl[c][1]
        if stop = col_name then ok = "true"
      end
      if !ok then Throw("colnames:\n'" + stop + "' not found in table")
    end
    if start = null then start = self.tbl[1][1]
    if stop = null then stop = self.tbl[self.ncol()][1]

    for c = 1 to self.ncol() do
      col_name = self.tbl[c][1]
      if col_name = start then started = "true"

      if started and !stopped then do
        if new_names = null
          then a_colnames = a_colnames + {col_name}
          else self.tbl[c][1] = new_names[c]
      end

      if col_name = stop then stopped = "true"
    end

    if new_names = null then return(a_colnames)
  EndItem

  /*doc
  Returns an array of column types. Possible types returned are:

    * short
    * long
    * double
    * string
  */

  Macro "coltypes" do

    // Argument checking
    if self.is_empty() then return()

    colnames = self.colnames()
    dim a_types[colnames.length]
    for c = 1 to colnames.length do
      colname = colnames[c]

      v = self.get_col(colname)
      a_types[c] = v.type
    end

    return(a_types)
  EndItem

  /*doc
  Returns a column of the data frame as a vector. Normally, something like this
  can be used:

  df.tbl.colname

  However, for reserved words like length, this won't work:

  df.tbl.length

  get_col() uses df.tbl.("length") to avoid this problem.

  Inputs
    * `field_names`
      * String or array/vector of strings
      * Field name(s) to get vector(s) for.

  Returns
    a vector of table data given a field name. If given an array of
    field names, returns an array of vectors.
  */

  Macro "get_col" (field_names) do

    // Argument checking
    if self.is_empty() then return()
    type = TypeOf(field_names)
    if type = "null" then Throw("get_col: 'field_names' not provided")
    if !self.in(type, {"string", "vector", "array"})
      then Throw("get_col: 'field_names' must be string, array, or vector")
    if type = "vector" then field_names = V2A(field_names)

    if type = "string" then do
      v = self.tbl.(field_names)
      return(v)
    end

    if type = "array" then do
      for name in field_names do
        a = a + {self.tbl.(name)}
      end
      return(a)
    end
  EndItem

  /*dontdoc
  Deprecated.
  */

  Macro "get_vector" do
    Throw("'get_vector' is deprecated. Now called 'get_col'")
  EndItem

  /*doc
  Returns an array of row values from a data frame given a row number.

  Inputs
    * `row_num`
      * Numeric
      * Number of row to retrieve data from.

    * `fields`
      * Optional string or array
      * Field(s) to return values for. Defaults to all fields.
      
    * `named`
      * Optional true/false
      * If true (the default), the returned array will be a named array using the column 
        names (e.g: row.column1 = 5, row.column2 = 9).
        If false, the returned array is just a simple array of values (e.g.
        {5, 9}).
  */

  Macro "get_row" (row_num, fields, named) do

    if row_num = null then Throw("'row_num' not provided")
    if TypeOf(row_num) <> "int" and TypeOf(row_num) <> "double"
      then Throw("'row_num' must be a number")
    if row_num > self.nrow()
      then Throw("'row_num' is greater than the number of rows")
    type = TypeOf(fields)
    if type = "null" 
      then fields = self.colnames()
      else if type = "string"
        then fields = {fields}
        else if type = "vector"
          then fields = V2A(fields)
          else if type <> "array"
            then Throw("If provided, 'fields' must be an array, vector, or string")
    if named = null then named = "true"

    for field in fields do
      v = self.tbl.(field)
      if named 
        then array.(field) = v[row_num]
        else array = array + {v[row_num]}
    end

    return(array)
  EndItem

  /*doc
  Converts a data frame object into a standard, named array where each named
  item is a vector of data. This can be accomplished directly using 'df.tbl'.
  */

  Macro "to_array" do
    if self.is_empty() then return(0)
    return(self.tbl)
  EndItem

  /*doc
  Converts a data frame into a named array of the same format returned by
  "Read Parameter File".
  
  Returns
    * A named array
  */
  
  Macro "to_params" do
  
    temp_file = GetTempFileName(".csv")
    self.write_csv(temp_file)
    params = RunMacro("Read Parameter File", temp_file)
    DeleteFile(temp_file)
    return(params)
  EndItem

  /*doc
  Returns
    * The number of columns or 0 if the table is empty
  */

  Macro "ncol" do
    if self.is_empty() then return(0)
    return(self.tbl.length)
  EndItem

  /*doc
  Returns
    * The number of rows or 0 if the table is empty
  */

  Macro "nrow" do
    if self.is_empty() then return(0)
    return(self.tbl[1][2].length)
  EndItem

  /*doc
  Checks that the data frame is valid.

  Returns
    * True/False
  */
  Macro "check" do
    if self.is_empty() then return()

    // Make sure that tbl property is an array
    if TypeOf(self.tbl) <> "array" then Throw("'tbl' property is not an array")

    // Convert all columns to vectors, check length, and remove periods from
    // names.
    for i = 1 to self.tbl.length do
      colname = self.tbl[i][1]

      // Type check
      type = TypeOf(self.tbl.(colname))
      if type <> "vector" then do
        if type <> "array"
          then self.tbl.(colname) = {self.tbl.(colname)}
        self.tbl.(colname) = A2V(self.tbl.(colname))
      end

      // Length check
      if self.tbl.(colname).length <> self.nrow() then
        Throw("check: '" + colname + "' has different length than first column")

      // Remove periods, which TC interprets as viewname.fieldname
      newname = Substitute(colname, ".", "_", )
      self.tbl[i][1] = newname
    end
    // Check field descriptions
    if self.desc <> null then do
      for i = 1 to self.desc.length do
        colname = self.desc[i][1]
        if self.tbl.(colname).length = null then Throw(
          "Data frame has a field description for a field not present in table."
        )
      end
    end
  EndItem

  /*doc
  Checks that the Caliper software is recent enough to run dataframe functions.
  */

  Macro "check_software" do
    program_info = GetProgram()
    name = program_info[2]
    build = program_info[4]
    if name = "TransCAD" and build < 7 then Throw("TransCAD 7 or later is required.")
    if name = "TransModeler" and build < 4 then Throw("TransModeler 4 or later is required.")
    if name = "Maptitude" then Throw("Not compatible with Maptitude")
  EndItem

  /*doc
  Adds a field to the data frame.

  Inputs
    * name
      * String
      * Field name
    * data
      * Single value, array, or vector
      * For an empty string field, use `""`
      * For an empty numeric field, use `null`
  */

  Macro "mutate" (name, data) do

    data_type = TypeOf(data)
    if data_type <> "array" and data_type <> "vector" then do
      if data_type = "int" or data_type = "null" then type = "Integer"
      else if data_type = "double" then type = "Real"
      else if data_type = "string" then type = "String"
      else Throw(
        "mutate: 'data' type not recognized.|" +
        "Should be array, vector, int, double, or string."
        )

      opts = null
      opts.Constant = data
      data = Vector(self.nrow(), type, opts)
    end

    self.tbl.(name) = data
    self.check()
  EndItem

  /*doc
  Changes the name of a column in a table object

  Inputs
  * `current_name`
    * String, array, or vector of strings
    * current name(s) of the field in the table
  * `new_name`
    * String, array, or vector of strings
    * desired new name(s) of the field
    * must be the same length as current_name
  */

  Macro "rename" (current_name, new_name) do

    // Argument checking
    if !self.in(TypeOf(current_name), {"string", "vector", "array"})
      then Throw("rename: 'current_name' must be string, array, or vector")
    if !self.in(TypeOf(new_name), {"string", "vector", "array"})
      then Throw("rename: 'new_name' must be string, array, or vector")
    if TypeOf(current_name)  = "string" then current_name = {current_name}
    if TypeOf(current_name)  = "vector" then current_name = V2A(current_name)
    if TypeOf(new_name)  = "string" then new_name = {new_name}
    if TypeOf(new_name)  = "vector" then new_name = V2A(new_name)
    if ArrayLength(current_name) <> ArrayLength(new_name)
      then Throw("rename: Field name arrays must be same length")
    if TypeOf(current_name[1]) <> "string"
      then Throw("rename: 'current_name' must contain strings")
    if TypeOf(new_name[1]) <> "string"
      then Throw("rename: 'new_name' must contain strings")

    for n = 1 to current_name.length do
      cName = current_name[n]
      nName = new_name[n]

      for c = 1 to self.tbl.length do
        if self.tbl[c][1] = cName then self.tbl[c][1] = nName
      end
    end
  EndItem

  /*doc
  Writes a data frame out to a csv file.

  Inputs
    * file
      * String
      * full path of csv file
  */
  Macro "write_csv" (file) do

    // Check for required arguments
    if file = null then Throw("write_csv: no file provided")
    if Right(file, 3) <> "csv"
      then Throw("write_csv: file name must end with '.csv'")

    // Check validity of table
    self.check()

    // Create a view and export to csv
    vw = self.create_view()
    ExportView(vw + "|", "CSV", file, , {"CSV Header": "true"})
    CloseView(vw)
    DeleteFile(Substitute(file, ".csv", ".DCC", ))
  EndItem

  /*doc
  Writes the data frame to a bin file.

  Inputs
    * file
      * String
      * Full path of bin file
  */

  Macro "write_bin" (file) do

    // Argument check
    if file = null then Throw("write_bin: no file provided")
    if Right(file, 3) <> "bin"
      then Throw("write_bin: file name must end with '.bin'")

    // Create a view and export to bin
    vw = self.create_view()
    ExportView(vw + "|", "FFB", file, , )
  EndItem

  /*doc
  Get column width(s)

  Inputs
    * `field_names`
      * Optional string or array/vector of strings If provided, the width of the
        specified column(s) will be returned. Otherwise, a vector of all column
        widths will be returned.
  */

  Macro "colwidths" (field_names) do

    // Argument check
    type = TypeOf(field_names)
    if type = "null" then field_names = self.colnames()
    if type = "string" then do
      field_names = {field_names}
      was_string = "True"
    end
    if type = "vector" then field_names = V2A(field_names)

    dim final[field_names.length]
    for f = 1 to field_names.length do
      field_name = field_names[f]

      v = self.get_col(field_name)
      v = if v.type <> "string" then String(v) else v
      v = StringLength(v)
      len = ArrayMax(V2A(v))

      final[f] = len
    end

    final = if was_string then final[1] else A2v(final)

    return(final)
  EndItem

  /*doc
  Converts a view into a data frame.

  Useful if you want to specify a selection set or already have a view open.

  Inputs (in a named array)
    * `view`
      * String
      * TC view name
    * `set`
      * Optional string
      * set name
    * `fields`
      * Optional string or array/vector of strings
      * Array/Vector of columns to read. If null, all columns are read.
    * `expr_vars`
      * Optional named array
      * If provided, the `Normalize Expression` macro will be run on the column
        vectors.
    * `null_to_zero`
      * Optional string (true/false)
      * Whether to convert null values to zero. Defaults to false.
    * `include_descriptions`
      * Optional string (true/false)
      * Whether to include field descriptions. Not applicable for all table types.
      * Defaults to false.

  Returns
    * A data frame object
  */

  Macro "read_view" (MacroOpts) do

    view = MacroOpts.view
    set = MacroOpts.set
    fields = MacroOpts.fields
    expr_vars = MacroOpts.expr_vars
    null_to_zero = MacroOpts.null_to_zero
    include_descriptions = MacroOpts.include_descriptions

    // Check for required arguments and
    // that data frame is currently empty
    if view = null then view = GetLayer()
    if view = null then view = GetView()
    if view = null
      then Throw(
        "read_view: Required argument 'view' missing and no\n" +
        "view or layer is open."
      )
    if !self.is_empty() then Throw("read_view: data frame must be empty")
    type = TypeOf(fields)
    if type <> "null" then do
      if type = "string" then fields = {fields}
      if type = "vector" then fields = V2A(fields)
      if type <> "array"
        then Throw("read_view: 'fields' must be string, vector, or array")
    end else do
      fields = GetFields(view, )
      fields = fields[1]
    end
    if include_descriptions then do
      {class, spec} = GetViewTableInfo(view)
      if class = null then Throw(
        "Field descriptions not supported for joined views"
      )
      if !self.in(class, {"FFB", "RDM", "CDF"}) then Throw(
        "Field descriptions not supported for '" + class + "' class.\n" +
        "Only .bin, .dbd, and .cdf views/layers are supported."
      )
    end

    // When a view has too many rows, a "???" will appear in the editor
    // meaning that TC did not load the entire view into memory.
    // Creating a selection set will force TC to load the entire view.
    SetView(view)
    // qry = "Select * where nz(" + fields[1] + ") >= 0"
    // SelectByQuery("temp", "Several", qry)
    SelectAll("temp")
    DeleteSet("temp")
    
    opts = null
    opts.[Missing as Zero] = null_to_zero
    data = GetDataVectors(view + "|" + set, fields, opts)
    for f = 1 to fields.length do
      field = fields[f]
      if data != null then self.tbl.(field) = data[f]

      if include_descriptions then do
        description = GetFieldDescription(view + "." + field)
        if description <> null
          then self.desc.(field) = GetFieldDescription(view + "." + field)
      end
    end

    self.check()

    if expr_vars <> null then self.norm_expr(expr_vars)
  EndItem

  /*doc
  Simple wrapper to `read_view` that reads bin files directly.

  Inputs
    * `file`
      * File path string
    * `fields`
      * Optional string or array/vector of strings
      * Array/Vector of columns to read. If null, all columns are read.
    * `expr_vars`
      * Optional named array
      * If provided, the `Normalize Expression` macro will be run on the column
        vectors.      
  */

  Macro "read_bin" (file, fields, expr_vars) do
    // Check file and extension
    if file = null then Throw("read_bin: 'file' not provided")
    if GetFileInfo(file) = null
      then Throw("read_bin: 'file'\n" + file + "\n" + "does not exist")
    {drive, folder, name, ext} = SplitPath(file)
    if ext <> ".bin"
      then Throw("read_bin: 'file'" + file + "\n" + "is not a .bin")

    opts = null
    opts.view = OpenTable("view", "FFB", {file})
    opts.fields = fields
    opts.expr_vars = expr_vars
    opts.include_descriptions = "true"
    self.read_view(opts)
    CloseView(opts.view)
  EndItem

  /*doc
  Simple wrapper to `read_view` that reads csv files directly.

  Inputs
    * `file`
      * File path string
    * `fields`
      * Optional string or array/vector of strings
      * Array/Vector of columns to read. If null, all columns are read.
    * `expr_vars`
      * Optional named array
      * If provided, the `Normalize Expression` macro will be run on the column
        vectors.      
  */

  Macro "read_csv" (file, fields, expr_vars) do
    // Check file and extension
    if file = null then Throw("read_csv: 'file' not provided")
    if GetFileInfo(file) = null
      then Throw("read_csv: 'file'\n" + file + "\n" + "does not exist")
    {drive, folder, name, ext} = SplitPath(file)
    if ext <> ".csv"
      then Throw("read_csv: 'file'" + file + "\n" + "is not a .csv")

    opts = null
    opts.view = OpenTable("view", "CSV", {file})
    opts.fields = fields
    opts.expr_vars = expr_vars
    self.read_view(opts)
    CloseView(opts.view)

    // Remove the .DCC
    DeleteFile(Substitute(file, ".csv", ".DCC", ))
  EndItem

  /*doc
  A wrapper to read_view that reads DBD files directly.

  Because there can be multiple layers per file, you must specify which layer
  to read.

  Inputs
    * `file`
      * String
      * Full path to the DBD file to read
    * `layer`
      * String
      * Layer name in the DBD to read
    * `fields`
      * Optional array of strings
      * Fields to read in (null for all fields)

  Returns
    * A data frame of the data in `layer`.
  */

  Macro "read_dbd" (file, layer, fields, expr_vars) do
    // Check file and extension
    if GetFileInfo(file) = null
      then Throw("read_dbd: file does not exist")
    {drive, folder, name, ext} = SplitPath(file)
    if ext <> ".dbd" then Throw("read_dbd: file not a .dbd")
    // Check that layer name is valid
    a_layers = GetDBLayers(file)
    if !self.in(layer, a_layers) then Throw("read_dbd: 'layer' not in 'file'")

    opts = null
    opts.view = AddLayerToWorkspace(layer, file, layer)
    opts.fields = fields
    opts.expr_vars = expr_vars
    self.read_view(opts)
    DropLayerFromWorkspace(layer)
  EndItem

  /*doc
  This macro takes data from a data frame and puts it into a view.  Columns are
  created if necessary. All column in the dataframe are written to the view. To
  save time, use `df.select()` before calling `df.update_view()` to choose only 
  the columns that need updating.

  Inputs
    * `view`
      * String
      * TC view name
    * `set`
      * Optional string
      * set name
  */

  Macro "update_view" (view, set) do

    // Check for required arguments and
    // that data frame is not currently empty
    if self.is_empty() then Throw("update_view: data frame is empty")
    if view = null
      then Throw("update_view: Required argument 'view' missing.")

    fields = self.colnames()
    for field in fields do
      field_type = self.tbl.(field).type

      if self.in(field_type, {"integer", "short", "long"}) then type = "Integer"
      else if field_type = "string" then type = "Character"
      else type = "Real"

      width = self.new_field_width(self.tbl.(field))
      width = max(5, width)
      a_fields =  {{field, type, width, 2,,,, ""}}
      RunMacro("Add Fields", {view: view, a_fields: a_fields})
    end

    SetDataVectors(view + "|" + set, self.tbl, )

    // Field descriptions
    if TypeOf(self.desc) <> "null" then do
      {class, spec} = GetViewTableInfo(view)
      if self.in(class, {"FFB", "RDM", "CDF"}) then do
        a_fields = null
        for d = 1 to self.desc.length do
          a_fields = a_fields + {self.desc[d][1]}
          a_descs = a_descs + {self.desc[d][2]}
        end

        RunMacro("Add Field Description", view, a_fields, a_descs)
      end
    end
  EndItem

  /*dontdoc
  Helper to update_view().
  Determines the maximum width needed for a field.

  Inputs
    * `data`
      * Array or vector

  Returns
    * The max width of the data
  */

  Macro "new_field_width" (data) do

    if TypeOf(data) = "array" then data = A2V(data)
    if TypeOf(data) <> "vector"
      then Throw("new_field_width: 'data' must be array or vector")

    if data.type <> "string" then data = String(data)
    widths = StringLength(data)
    width = widths.max()

    // width = 0
    // iter = min(100, data.length)
    // for i = 1 to iter do
    //   if StringLength(data[i]) > width then width = StringLength(data[i])
    // end

    return(width)
  EndItem

  /*doc
  Simple wrapper to `update_view` that allow you to update
  BIN files without having to open them first.
  Does not support selection sets. If working on a selection set,
  the view is already open - see `update_view`.

  CSVs cannot be updated in this way - TransCAD cannot modify the
  fields or data of an opened CSV file.

  Inputs
    * `bin_file`
      * String
      * Path of file to update
  */

  Macro "update_bin" (bin_file) do

    // Check file and extension
    if GetFileInfo(bin_file) = null
      then Throw("update_bin: file does not exist")
    {drive, folder, name, ext} = SplitPath(bin_file)
    if ext <> ".bin" then Throw("update_bin: file not a .bin")

    // Open the file and update it
    view = OpenTable("view", "FFB", {bin_file})
    self.update_view(view)
    CloseView(view)
  EndItem

  /*doc
  Reads a matrix file (.mtx).

  Inputs
    * `file`
      * String
      * Full file path of matrix
    * `cores`
      * String or array of strings
      * Core names to read - defaults to all cores
    * `ri`
      * String
      * Row index to use. Defaults to the default index.
    * `ci`
      * String
      * Column index to use.  Defaults to the default index.
    * `all_cells`
      * Boolean
      * Whether to include every ij pair in the data frame.  Defaults to "true".
      * Set to "false" to drop cells with missing values.

  Returns
    * Nothing. Updates the data frame with matrix data in tabular format.
  */

  Macro "read_mtx" (file, cores, ri, ci, all_cells) do

    // Check arguments and set defaults if needed
    if !self.is_empty() then Throw("read_mtx: data frame must be empty")
    {drive, folder, name, ext} = SplitPath(file)
    if ext <> ".mtx" then Throw("read_mtx: file name must end in '.mtx'")
    mtx = OpenMatrix(file, )
    a_corenames = GetMatrixCoreNames(mtx)
    if cores = null then cores = a_corenames
    if TypeOf(cores) = "string" then cores = {cores}
    if TypeOf(cores) <> "array" then
      Throw("read_mtx: 'cores' must be either an array, string, or null")
    for c = 1 to cores.length do
      if !self.in(cores[c], a_corenames)
        then Throw("read_mtx: core '" + cores[c] + "' not found in matrix")
    end
    {d_ri, d_ci} = GetMatrixIndex(mtx)
    if ri = null then ri = d_ri
    if ci = null then ci = d_ci
    {row_inds, col_inds} = GetMatrixIndexNames(mtx)
    if !self.in(ri, row_inds)
      then Throw("read_mtx: row index '" + ri + "' not found in matrix")
    if !self.in(ci, col_inds)
      then Throw("read_mtx: column index '" + ci + "' not found in matrix")
    if all_cells = null or all_cells then all_cells = "Yes"
    else all_cells = "No"

    // Set the matrix index and export to a table
    SetMatrixIndex(mtx, ri, ci)
    file_name = GetTempFileName(".bin")
    opts = null
    opts.Complete = all_cells
    opts.Tables = cores
    CreateTableFromMatrix(mtx, file_name, "FFB", opts)

    // Read exported table into view
    self.read_bin(file_name)

    // Clean up workspace
    DeleteFile(file_name)
    DeleteFile(Substitute(file_name, ".bin", ".DCB", ))
  EndItem

  /*dontdoc
  Creates a MEM table view of the data frame.  This is primarily a helper
  function for other dataframe methods, and its purpose is to make GISDK
  functions/operations available for a data frame. The view is usually read back
  into a data frame after some work has been done on it.

  Returns:
  view_name:  Name of the view as opened in TrandCAD
  */

  Macro "create_view" do

    // Create the field info array for CreateTable()
    colnames = self.colnames()
    coltypes = self.coltypes()
    colwidths = self.colwidths()
    for c = 1 to colnames.length do
      colname = colnames[c]
      coltype = coltypes[c]
      width = max(colwidths[c], 10)

      if coltype = "short" then coltype = "Integer"
      else if coltype = "long" then coltype = "Integer"
      else if coltype = "double" then coltype = "Real"
      else if coltype = "string" then coltype = "String"

      deci = if coltype = "Real" then 2 else 0
      a_field_info = a_field_info + {{colname, coltype, width, deci, }}
    end

    // Create table
    view_name = self.unique_view_name()
    view_name = CreateTable(view_name, , "MEM", a_field_info, )

    // Add empty rows
    opts = null
    opts.[empty records] = self.nrow()
    AddRecords(view_name, , , opts)

    // Fill in data
    self.update_view(view_name)

    return(view_name)
  EndItem

  /*doc
  Avoids duplicating view names by using an odd name and checking to
  make sure the view does not already exist.

  Returns
    * A unique view name.
  */

  Macro "unique_view_name" do
    view_names = GetViews()
    if view_names.length = 0 then do
      view_name = "dataframe1"
    end else do
      view_names = view_names[1]
      num = 0
      exists = "True"
      while exists do
        num = num + 1
        view_name = "dataframe" + String(num)
        exists = if (ArrayPosition(view_names, {view_name}, ) <> 0)
          then "True"
          else "False"
      end
    end

    return(view_name)
  EndItem


  /*doc
  Displays the contents of a data frame in a visible editor window in
  TransCAD.
  
  Inputs
    * label
      * Optional string
      * Display name for TC editor window.
  */

  Macro "view" (label) do  
    
    // If view() is called multiple times, the windows will be arranged
    // in a 3x3 grid. The size and positions units below are % of TC window.
    size_x = 33
    size_y = 33
    {, , titles} = GetWindows("Editor")
    num_windows = titles.length
    if  num_windows > 0 then do
      column = Mod(num_windows, 3)
      pos_x = R2I(size_x * column)
      row = Floor(num_windows / 3)
      pos_y = R2I(size_y * row)
    end else do
      pos_x = 0
      pos_y = 0
    end
    
    if label = null then label = "data frame"
    view_name = self.create_view()
    window = CreateEditor(
      label, view_name + "|", , {{"Position", pos_x, pos_y}}
    )
    SetWindowSize(window, size_x, size_y)
  EndItem
  
  /*doc
  Deprecated. Now called "view".
  */

  Macro "create_editor" do
    Throw("'create_editor()' is deprecated. Use 'view()'.")
  EndItem
  
  /*doc
  Removes field(s) from a table

  Inputs
    * `fields`
      * String or array of strings
      * fields to drop from the data frame
  */

  Macro "remove" (fields) do

    // Argument checking and type handling
    if fields = null then Throw("remove: no fields provided")
    if TypeOf(fields) = "string" then fields = {fields}

    for f = 1 to fields.length do
      self.tbl.(fields[f]) = null
    end
  EndItem

  /*doc
  Like dplyr or SQL, `select` returns a table with only
  the columns listed in `fields`. To remove columns, see remove().

  Inputs
    * `fields`
      * String or array/vector of strings
      * fields to keep in the data frame
  */

  Macro "select" (fields) do

    // Argument checking and type handling
    type = TypeOf(fields)
    if type = "null" then Throw("select: no fields provided")
    if type = "vector" then fields = V2A(fields)
    if type = "string" then fields = {fields}

    data = null
    for f = 1 to fields.length do
      field = fields[f]

      // Check to see if name is in table
      if !(self.in(field, self.colnames()))
        then Throw("select: field '" + field + "' not in data frame")
      data.(field) = self.get_col(field)
    end

    self.tbl = data
  EndItem

  /*doc
  Checks if `find` is listed anywhere in `space`.

  Inputs
    * find
      * String, numeric, array, or vector
      * The value to search for. If `find` is a vector or array, the entire
        vector/array is searched for.
    * space
      * Array, vector, or string
      * The search space.
      * If string, `find` must be string.

  Returns 
    * True/False
  */

  Macro "in" (find, space) do

    // Argument check
    find_type = TypeOf(find)
    if find_type = "null" then Throw("in: 'find' not provided")
    if find_type = "vector" then find = V2A(find)
    space_type = TypeOf(space)
    if space_type = "null" then Throw("in: 'space' not provided")
    if space_type = "vector" then space = V2A(space)
    if (space_type = "array" or space_type = "vector") and find_type <> "array"
      then find = {find}
    if space_type = "string" and find_type <> "string"
      then Throw("in: if variable 'space' is a string, `find` must be a string")

    if space_type = "string"
      then tf = if Position(space, find) <> 0 then "True" else "False"
      else tf = if ArrayPosition(space, find, ) <> 0 then "True" else "False"
    return(tf)
  EndItem

  /*dontdoc
  **This is the first version of the summarize() function and is deprecated.**
  
  This macro works with group_by() similar to dlpyr in R.
  Summary stats are calculated for the columns specified, grouped by
  the columns listed as grouping columns in the df.groups property.
  (Set grouping fields using group_by().)

  Inputs
    * agg
      * Options array listing field and aggregation info e.g.: 
        * agg.weight = {"sum", "avg"} (to sum and average 'weight')
        * agg.trips = "sum" (to sum 'trips')
      * The possible aggregations are:
        * first, sum, high, low, avg, stddev, count
    * in_place
      * Optional true/false
      * Defaults to true
      * If true, modifies the existing data frame. If false, returns a new
        data frame.

  Returns
    * A new data frame of the summarized input table object.
    * In the first example above, the aggregated fields would be sum_weight and 
      avg_weight
    * The last group field is also removed from .groups
  */

  Macro "summarize_deprecated" (agg, in_place) do

    if self.groups = null
      then Throw("summarize: use group_by() to set summary dimensions")
    for a = 1 to agg.length do
      if TypeOf(agg[a][2]) = "string"
        then agg[a][2] = {agg[a][2]}
    end
    if in_place = null then in_place = "true"

    new_df = self.copy()

    // Remove fields that aren't listed for summary or grouping
    for i = 1 to new_df.groups.length do
      a_selected = a_selected + {new_df.groups[i]}
    end
    for i = 1 to agg.length do
      a_selected = a_selected + {agg[i][1]}
    end
    new_df.select(a_selected)

    // Convert the TABLE object into a view in order
    // to leverage GISDKs SelfAggregate() function
    view = new_df.create_view()

    // Create a field spec for SelfAggregate()
    agg_field_spec = view + "." + new_df.groups[1]

    // Create the "Additional Groups" option for SelfAggregate()
    opts = null
    if new_df.groups.length > 1 then do
      for g = 2 to new_df.groups.length do
        opts.[Additional Groups] = opts.[Additional Groups] + {new_df.groups[g]}
      end
    end

    // Create the fields option for SelfAggregate()
    for i = 1 to agg.length do
      name = agg[i][1]
      stats = agg[i][2]

      proper_stats = null
      for j = 1 to stats.length do
        proper_stats = proper_stats + {{Proper(stats[j])}}
      end
      fields.(name) = proper_stats
    end
    opts.Fields = fields

    // Create the new view using SelfAggregate()
    agg_view = SelfAggregate("aggview", agg_field_spec, opts)

    // Read the view back into the data frame
    new_df.tbl = null
    opts = null
    opts.view = agg_view
    new_df.read_view(opts)

    // The field names from SelfAggregate() are messy.  Clean up.
    // The first fields will be of the format "GroupedBy(ID)".
    // Next is a "Count(bin)" field.
    // Then there is a first field for each group variable ("First(ID)")
    // Then the stat fields in the form of "Sum(trips)"

    // Set group columns back to original name
    for c = 1 to new_df.groups.length do
      new_df.tbl[c][1] = new_df.groups[c]
    end
    // Set the count field name
    new_df.tbl[new_df.groups.length + 1][1] = "Count"
    // Remove the First() fields
    new_df.tbl = ExcludeArrayElements(
      new_df.tbl,
      new_df.groups.length + 2,
      new_df.groups.length
    )
    // Change fields like Sum(x) to sum_x
    for i = 1 to agg.length do
      field = agg[i][1]
      stats = agg[i][2]
      for j = 1 to stats.length do
        stat = stats[j]

        current_field = "[" + Proper(stat) + "(" + field + ")]"
        new_field = lower(stat) + "_" + field
        new_df.rename(current_field, new_field)
      end
    end

    // Check if "Count" field should be removed. If "count" is present in any
    // of the field stats, then keep it.
    remove_count = "True"
    for a = 1 to agg.length do
      stats = agg[a][2]
      if new_df.in("count", stats) then remove_count = "False"
    end
    if remove_count then new_df.remove("Count")

    // Remove last grouping field
    new_df.groups = ExcludeArrayElements(new_df.groups, new_df.groups.length, 1)

    // Clean up workspace
    CloseView(view)
    CloseView(agg_view)
    
    if in_place
      then do
        self.tbl = new_df.tbl
        self.desc = new_df.desc
        self.groups = new_df.groups
      end else return(new_df)
  EndItem

  /*doc
  This macro works with group_by() similar to dlpyr in R.
  Summary stats are calculated for the columns specified, grouped by
  the columns listed as grouping columns in the df.groups property.
  (Set grouping fields using group_by().)

  Inputs
    * `fields`
      * String or array of strings
      * Field name(s) to summarize
    * `stats`
      * String or array of strings
      * Statistics to calculate:
        * first, sum, high, low, avg, stddev, count
    * `in_place`
      * Optional true/false
      * Defaults to true
      * If true, modifies the existing data frame. If false, returns a new
        data frame.

  Returns
    * A new data frame of the summarized input table object.
    * In the first example above, the aggregated fields would be sum_weight and 
      avg_weight
    * The last group field is also removed from .groups
  */

  Macro "summarize" (fields, stats, in_place) do

    // Check if the deprecated version of the function should be run
    if RunMacro("Is Named Array", fields) then do
      RunMacro(
        "Show Warning", "Using a named array for summarize() will be deprecated. " +
        "Update code to use the new, simpler style (see documentation)."
      )
      agg = fields
      in_place = stats
      if in_place 
        then self.summarize_deprecated(agg, in_place)
        else df = self.summarize_deprecated(agg, in_place)
      return(df)
    end
    
    if self.groups = null
      then Throw("summarize: use group_by() to set summary dimensions")
    fields = RunMacro("2A", fields)
    stats = RunMacro("2A", stats)
    if in_place = null then in_place = "true"

    new_df = self.copy()

    // Remove fields that aren't listed for summary or grouping
    a_selected = new_df.groups + fields
    new_df.select(a_selected)

    // Convert the TABLE object into a view in order
    // to leverage GISDKs SelfAggregate() function
    view = new_df.create_view()

    // Create a field spec for SelfAggregate()
    agg_field_spec = view + "." + new_df.groups[1]

    // Create the "Additional Groups" option for SelfAggregate()
    opts = null
    if new_df.groups.length > 1 then do
      for g = 2 to new_df.groups.length do
        opts.[Additional Groups] = opts.[Additional Groups] + {new_df.groups[g]}
      end
    end

    // Create the fields option for SelfAggregate()
    proper_stats = null
    for stat in stats do
      proper_stats = proper_stats + {{Proper(stat)}}
    end
    for field in fields do
      a_fields.(field) = proper_stats
    end
    opts.Fields = a_fields

    // Create the new view using SelfAggregate()
    agg_view = SelfAggregate("aggview", agg_field_spec, opts)

    // Read the view back into the data frame
    new_df.tbl = null
    opts = null
    opts.view = agg_view
    new_df.read_view(opts)

    // The field names from SelfAggregate() are messy.  Clean up.
    // The first fields will be of the format "GroupedBy(ID)".
    // Next is a "Count(bin)" field.
    // Then there is a first field for each group variable ("First(ID)")
    // Then the stat fields in the form of "Sum(trips)"

    // Set group columns back to original name
    for c = 1 to new_df.groups.length do
      new_df.tbl[c][1] = new_df.groups[c]
    end
    // Set the count field name
    new_df.tbl[new_df.groups.length + 1][1] = "Count"
    // Remove the First() fields
    new_df.tbl = ExcludeArrayElements(
      new_df.tbl,
      new_df.groups.length + 2,
      new_df.groups.length
    )
    // Change fields like Sum(x) to sum_x
    for field in fields do
      for stat in stats do
        current_field = "[" + Proper(stat) + "(" + field + ")]"
        new_field = lower(stat) + "_" + field
        new_df.rename(current_field, new_field)
      end
    end

    // Check if "Count" field should be removed.
    if !new_df.in("count", stats) then new_df.remove("Count")

    // Remove last grouping field
    new_df.groups = ExcludeArrayElements(new_df.groups, new_df.groups.length, 1)

    // Clean up workspace
    CloseView(view)
    CloseView(agg_view)
    
    if in_place
      then do
        self.tbl = new_df.tbl
        self.desc = new_df.desc
        self.groups = new_df.groups
      end else return(new_df)
  EndItem

  /*doc
  Applies a query to a table object.

  Inputs
    * `query`
      * String
      * Valid TransCAD query (e.g. "ID = 5" or "Name <> 'Sam'")
      * You do not have to include "Select * where" in the query string, but 
        doing so will still work.
  */

  Macro "filter" (query) do

    // Argument check
    if query = null then Throw("filter: query is missing")
    if TypeOf(query) <> "string" then Throw("filter: query must be a string")

    view = self.create_view()
    SetView(view)
    query = RunMacro("Normalize Query", query)
    nrow = SelectByQuery("set", "Several", query)
    // if no records are found, return an empty df object.
    self.tbl = null
    if nrow = 0 then do
      CloseView(view)
      return()
    end
    // Otherwise, read in the filtered view
    opts = null
    opts.view = view
    opts.set = "set"
    self.read_view(opts)

    // Clean up workspace
    CloseView(view)
  EndItem


  /*doc
  Joins two data frame objects.

  Inputs
    * slave_tbl
      * data frame object
    * m_id
      * String or array of strings
      * The id fields from the master table to use for join.  Use an array to
        specify multiple fields.
    * s_id
      * Optional string or array of strings
      * The id fields from the slave table to use for join. Use an array to
        specify multiple fields.
      * Defaults to m_id
  */

  Macro "left_join" (slave_tbl, m_id, s_id) do

    // Argument check
    self.check()
    slave_tbl.check()
    if s_id = null then s_id = m_id
    if TypeOf(m_id) = "string" then m_id = {m_id}
    if TypeOf(s_id) = "string" then s_id = {s_id}
    if m_id.length <> s_id.length then
      Throw("left_join: 'm_id' and 's_id' are not the same length")

    // Check that master and slave fields are present in the table
    colnames = self.colnames()
    for field in m_id do
      if !self.in(field, colnames) then Throw(
        "left_join: master field '" + field + "' not found in master table"
      )
    end
    colnames = slave_tbl.colnames()
    for field in s_id do
      if !self.in(field, colnames) then Throw(
        "left_join: slave field '" + field + "' not found in slave table"
      )
    end

    // To avoid duplication of field names. Add "x" to all master fields and
    // add "y" to all slave fields. To avoid modifying the slave table, make
    // a copy of it first.
    slave_copy = slave_tbl.copy()
    v_colnames = self.colnames()
    for c in v_colnames do
      self.rename(c, c + "_x")
    end
    v_colnames = slave_copy.colnames()
    for c in v_colnames do
      slave_copy.rename(c, c + "_y")
    end
    // Do the same for m_id and s_id arrays
    m_id = V2A(A2V(m_id) + "_x")
    s_id = V2A(A2V(s_id) + "_y")

    // Create views of both tables
    master_view = self.create_view()
    slave_view = slave_copy.create_view()

    // Create field specs for master and slave fields
    m_spec = V2A(master_view + "." + A2V(m_id))
    s_spec = V2A(slave_view + "." + A2V(s_id))

    // Join views together
    jv = JoinViewsMulti("jv", m_spec, s_spec, {{"O", 1}})
    self.tbl = null
    opts = null
    opts.view = jv
    self.read_view(opts)
    // Remove slave fields
    for sf in s_id do
      self.remove(sf)
    end

    // For the remaining fields, remove the "_x" or "_y" unless there are
    // duplicates.
    v_colnames = A2V(self.colnames())
    v_rawnames = Left(v_colnames, StringLength(v_colnames) - 2)
    for c = 1 to v_colnames.length do
      colname = v_colnames[c]
      rawname = v_rawnames[c]

      // Create an array of raw field names without the current name. If the
      // current raw name is still found in this array, it means the field is
      // duplicated.
      a_search = ExcludeArrayElements(V2A(v_rawnames), c, 1)
      pos = ArrayPosition(a_search, {rawname}, )
      if pos = 0 then self.rename(colname, rawname)
    end

    // Clean up the workspace
    CloseView(jv)
    CloseView(master_view)
    CloseView(slave_view)
  EndItem

  /*doc
  Concatenates multiple column values into a single column

  Inputs
    * `cols`
      * Vector or array of strings
      * column names to unite
    * `new_col`
      * String
      * Name of new column to place results
    * `sep`
      * String
      * Separator to use between values
      * Defaults to `_`
  */

  Macro "unite" (cols, new_col, sep) do

    // Argument check
    if sep = null then sep = "_"
    cols_type = TypeOf(cols)
    if cols_type = "vector" then cols = V2A(cols)
    if cols_type <> "array" and cols_type <> "vector"
      then Throw("unite: 'cols' must be an array or vector")
    if new_col = null then Throw("unite: `new_col` not provided")

    for c = 1 to cols.length do
      col = cols[c]

      vec = self.tbl.(col)
      vec = if (vec.type = "string")
        then self.tbl.(col)
        else String(self.tbl.(col))
      self.tbl.(new_col) = if (c = 1)
        then vec
        else self.tbl.(new_col) + sep + vec
    end
  EndItem

  /*doc
  Opposite of `unite()``.  Separates a column based on a delimiter

  Inputs
    * col
      * String
      * Name of column to seaprate
    * new_cols
      * Array of strings
      * Names of new columns
    * sep
      * Optional string
      * Delimter to use to parse
      * Defaults to "_"
    * keep_orig_col
      * Optional true/false
      * Whether to preserve the original column
      * Defaults to false
  */

  Macro "separate" (col, new_cols, sep, keep_orig_col) do

    // Argument check
    if sep = null then sep = "_"
    if col = null then Throw("separate: `col` not provided")
    type = TypeOf(new_cols)
    if type = "vector" then new_cols = V2A(new_cols)
    if type <> "array" and type <> "vector"
      then Throw("separate: 'new_cols' must be an array or vector")
    vec = self.tbl.(col)
    if TypeOf(vec[1]) <> "string" then
      Throw("separate: column '" + col + "' doesn't contain strings")

    dim array[new_cols.length, self.nrow()]
    for r = 1 to self.nrow() do
      vec = self.tbl.(col)
      string = vec[r]
      parts = ParseString(string, sep)

      // Handle if parts is shorter than new_cols
      if parts.length < new_cols.length then do
        for p = parts.length + 1 to new_cols.length do
          parts = parts + {""}
        end
      end

      // Handle if parts is longer than new_cols
      if parts.length > new_cols.length then do
        resize = null
        for p = 1 to parts.length do
          part = parts[p]
          
          if p <= new_cols.length then resize = resize + {part}
          else resize[new_cols.length] = resize[new_cols.length] + sep + part
        end
        parts = CopyArray(resize)
      end

      for p = 1 to parts.length do
        value = parts[p]

        // Convert any string-number into a number
        if TypeOf(value) = "string" then do
          value = if value = "0"
            then 0
            else if Value(value) = 0
              then value
              else Value(value)
        end

        array[p][r] = value
      end
    end

    // fill data frame
    for c = 1 to new_cols.length do
      self.tbl.(new_cols[c]) = array[c]
    end

    // remove original column
    if !keep_orig_col then self.tbl.(col) = null

    self.check()
  EndItem

  /*doc
  Transform data from long to wide format.

  Reverse of `gather`. Creates new columns. The column names come from the "key"
  field. The values of the columns come from the "value" field.

  See this [cheatsheet](https://github.com/rstudio/cheatsheets/blob/master/data-import.pdf)
  for more details (second page has spread/gather). Note that dplyr is 
  transitioning to "pivot_wider" and "pivot_longer", so the cheatsheet may be
  updated to that in the future.

  Inputs
    * `key`
      * String
      * The column whose values will become new column names.
    * `value`
      * String
      * The column whose values will fill the new columns.
    * `fill`
      * String or number as appropriate
      * The string/number to fill into empty data cells of new columns
      * Defautls to null
  */

  Macro "spread" (key, value, fill) do

    // Argument check
    if key = null then Throw("spread: `key` missing")
    if value = null then Throw("spread: `value` missing")
    if !self.in(key, self.colnames()) then Throw("spread: `key` not in table")
    if !self.in(value, self.colnames()) then
      Throw("spread: `value` not in table")

    // Create a single-column data frame that concatenates all fields
    // except for key and value
    first_col = self.copy()
    first_col.tbl.(key) = null
    first_col.tbl.(value) = null
    // If more than one field remains in the table, unite them
    if first_col.ncol() > 1 then do
      unite = "True"
      join_col = "unite"
      a_unite_cols = first_col.colnames()
      first_col.unite(a_unite_cols, join_col, "%^&")
      first_col.select(join_col)
    end else do
      join_col = first_col.colnames()
      join_col = join_col[1]
    end
    vec = first_col.unique(join_col)
    first_col.mutate(join_col, vec)

    // Create a second working table.
    split = self.copy()
    // If necessary, combine columns in `split` to match `first_col` table
    if unite then split.unite(a_unite_cols, join_col, "%^&")
    a_unique_keys = split.unique(key)
    for k = 1 to a_unique_keys.length do
      key_val = a_unique_keys[k]

      // TransCAD requires field names to look like strings.
      // Add an "s" at start of name if needed.
      col_name = if TypeOf(key_val) <> "string"
        then "s" + String(key_val)
        else key_val

      temp = if split.tbl.(key) = key_val then split.tbl.(value) else null
      split.mutate(col_name, temp)

      // Create a sub table from `split` and join it to `first_col`
      sub = split.copy()
      sub.select({join_col, col_name})
      sub.filter(col_name + " <> null")
      first_col.left_join(sub, join_col, join_col)

      // Fill in any null values with `fill`
      first_col.tbl.(col_name) = if first_col.tbl.(col_name) = null
        then fill
        else first_col.tbl.(col_name)
    end

    // Create final table
    self.tbl = null
    self.tbl.(join_col) = first_col.tbl.(join_col)
    if unite then self.separate(join_col, a_unite_cols, "%^&")
    first_col.tbl.(join_col) = null
    self.tbl = InsertArrayElements(self.tbl, self.tbl.length + 1, first_col.tbl)
  EndItem

  /*doc
  Transform data from wide to long format.

  Reverse of `spread`. Places the names of multiple columns into a single "key" 
  column and places the values of those multiple columns into a single "value"
  column.

  See this [cheatsheet](https://github.com/rstudio/cheatsheets/blob/master/data-import.pdf)
  for more details (second page has spread/gather). Note that dplyr is 
  transitioning to "pivot_wider" and "pivot_longer", so the cheatsheet may be
  updated to that in the future.

  Inputs
    * `gather_cols`
      * Array or vector of strings
      * Lists the columns to gather
    * `key`
      * String
      * Name of column that will hold `gather_col`'s column names
    * `value`
      * String
      * Name of column that will hold `gather_col`'s values
  */

  Macro "gather" (gather_cols, key, value) do

    // Argument check
    if key = null then key = "key"
    if value = null then value = "value"
    if TypeOf(gather_cols) <> "vector" and TypeOf(gather_cols) <> "array"
      then Throw("gather: 'gather_cols' must be an array or vector")
    if gather_cols.length = 0 then Throw("gather: 'gather_cols' missing")

    // Create a seed df that will be used to build new table
    seed = self.copy()
    seed.remove(gather_cols)

    // build new table by looping over each of gather_cols
    for c = 1 to gather_cols.length do
      col = gather_cols[c]

      // use the seed df to create a simple table
      temp = seed.copy()
      opts = null
      opts.Constant = col
      v_key = Vector(self.nrow(), "string", opts)
      temp.mutate(key, v_key)
      temp.mutate(value, self.tbl.(col))

      // If first gather column, create final table from temp.
      // Otherwise, append temp to final table
      if c = 1 then final = temp.copy()
      else final.bind_rows(temp)
    end

    // Set self to final
    self.tbl = final.tbl
  EndItem

  /*doc
  Combines the rows of two tables.
  
  They must have the same columns.

  Inputs
    * `df`
      * data frame object
      * data frame that gets appended
  */

  Macro "bind_rows" (df) do

    // Check that tables have same columns. Any columns not found in either
    // table are added with null values.
    colnames1 = self.colnames()
    colnames2 = df.colnames()
    for col in colnames1 do
      if !self.in(col, colnames2) then do 
        v = self.tbl.(col)
        if TypeOf(v[1]) = 'string'
          then value = ""
          else value = null
        df.mutate(col, value)
      end
    end
    for col in colnames2 do
      if !self.in(col, colnames1) then do 
        v = df.tbl.(col)
        if TypeOf(v[1]) = 'string'
          then value = ""
          else value = null
        self.mutate(col, value)
      end
    end
    
    // Make sure both tables are vectorized and pass all checks
    self.check()
    df.check()

    // Combine tables
    all_colnames = self.unique(colnames1 + colnames2)
    for col_name in all_colnames do
      a1 = V2A(self.tbl.(col_name))
      a2 = V2A(df.tbl.(col_name))
      self.tbl.(col_name) = a1 + a2
    end

    // Final check
    self.check()
  EndItem

  /*doc
  Creates a field of categories based on a continuous numeric field.

  Inputs (in named array)
    * `in_field`
      * String
      * Name of continuous field to be "binned"
    * `bins`
      * Number or array/vector of numbers
      * If a number:
        * Then it represents the number of bins to create.  The range of
          the `in_field` will be divided up evenly.
      * If an array/vector:
        * Each number listed represents the start of the bin. The end of the
          last bin is assumed to be the max value in the field.
          e.g. {0, 1} is:
          0 <= x < 1
          1 <= x < [max number]
    * `labels`
      * Optional array or vector of numbers or strings
      * Names of the bins.
      * If 'bins' is a list, length must be 1 less than the length of 'bins'.
      * If 'bins' is a number, then length must be the same as 'bins'.
      * If not provided, the bins will be labeled 1 - n
  */

  Macro "bin_field" (MacroOpts) do

    in_field = MacroOpts.in_field
    bins = MacroOpts.bins
    labels = MacroOpts.labels

    // Argument check
    if in_field = null then Throw("bin_field: 'in_field' not provided")
    if !self.in(in_field, self.colnames())
      then Throw("bin_field: 'in_field' not a column name in table")
    type = TypeOf(bins)
    if type = "null" then Throw("bin_field: 'bins' not provided")
    if type = "vector" then bins = V2A(bins)
    if labels <> null then do
      if !self.in(TypeOf(labels), {"array", "vector"})
        then Throw("bin_field: 'labels' must be an array or vector")
    end
    // Determine whether 'bins' is a number or array and number of bins
    bin_type = TypeOf(bins)
    if (bin_type = "int") then bin_num = bins
    else if (bin_type = "array") then bin_num = bins.length
    else Throw("bin_field: 'bins' must be number, array, or vector")
    // check length of 'labels' if provided
    if labels <> null then do
      if labels.length <> bin_num
        then Throw(
          "bin_field: 'labels' length must equal the number of bins"
        )
    end

    // Determine min/max values of 'in_field'
    max = VectorStatistic(self.tbl.(in_field), "max", )
    min = VectorStatistic(self.tbl.(in_field), "min", )

    // If 'bins' is a list, remove values outside in_field
    if bin_type = "list" then do

      for b = bin_num to 1 step -1 do
        bin = bins[b]

        if !(bin >= min and bin <= max) then do
          ExcludeArrayElements(bins, b, 1)
          if labels <> null then ExcludeArrayElements(labels, b, 1)
        end
      end
    end

    // If 'bins' is a number, then convert to an array of values
    if bin_type = "int" then do
      size = (max - min) / bin_num

      bins = {min}
      for b = 1 to bin_num do
        bins = bins + {min + size * b}
      end
    end

    // Create 'labels' if it is not provided
    if labels = null then do
      for b = 1 to bin_num do
        labels = labels + {b}
      end
    end

    // Convert 'bins' into from and to arrays and perform the binning process
    a_from = bins
    a_to = ExcludeArrayElements(bins, 1, 1) + {max}
    for i = 1 to labels.length do
      label = labels[i]
      from = a_from[i]
      to = if (i = labels.length)
        then a_to[i] + .01
        else a_to[i]

      v_label = if (self.tbl.(in_field) >= from and self.tbl.(in_field) < to)
        then label else v_label
    end

    self.mutate("bin", v_label)
  EndItem

  /*doc
  Takes an array or vector and returns a list of unique values
  in the same format.

  Inputs
    * `list`
      * String or a vector/array of values
      * If a string, it is assumed to be a column name in the data frame.
      * Otherwise, the vector/array input will be processed.
    * `drop_missing`
      * Optional true/false
      * Whether or not to drop missing (null/na) values from the vector
      * Defaults to "true"

  Returns
    * list of unique values (in ascending order)
    * Type matches the input type (vector or array)
  */

  Macro "unique" (list, drop_missing) do

    // Argument check
    if TypeOf(list) = "null" then Throw("unique: 'list' not provided")
    if not(self.in(TypeOf(list), {"string", "vector", "array"}))
      then Throw("unique: 'list' isn't a string, vector or array")
    // if a string is passed, attempt to find a column with that name
    if TypeOf(list) = "string" then do
      col = self.tbl.(list)
      if col.length = 0
        then Throw("unique: column '" + list + "' not in table")
        else list = col
    end
    if drop_missing = null then drop_missing = "true"

    opts = null
    opts.Unique = "true"
    opts.[Omit Missing] = drop_missing
    if TypeOf(list) = "vector" then do
      ret = SortVector(list, opts)
    end else do
      ret = SortArray(list, opts)
    end

    return(ret)
  EndItem

  /*doc
  Sorts a dataframe based on one or more columns
  
  Only ascending order is supported.

  Inputs
    * `fields`
      * String or array of strings
      * Names of fields to sort by
  */

  Macro "arrange" (fields) do

    // Argument checking
    if fields = null then Throw("arrange: 'fields' not provided")
    if TypeOf(fields) = "string" then fields = {fields}

    // The SortSet() function wants a long string. Convert the array
    fields_string = fields[1]
    for f = 2 to fields.length do
      fields_string = fields_string + ", " + fields[f]
    end

    // Create a set of all records to be sorted
    view = self.create_view()
    SetView(view)
    cols = self.colnames()
    first_col = cols[1]
    qry = "Select * where " + first_col + " <> null or " + first_col + " = null"
    SelectByQuery("set", "several", qry)

    // Sort the selection set using the string of fields
    SortSet("set", fields_string)

    // Reading in a sorted view won't respect the sort order. Must write
    // out to a new bin file and read back in.
    temp_file = GetTempFileName("*.bin")
    ExportView(view + "|set", "FFB", temp_file, , )
    CloseView(view)

    self.tbl = null
    self.read_bin(temp_file, )
  EndItem

  /*doc
  Run the "Normalize Expression" macro over columns in a data frame. Any
  {variables} found are evaluated by looking them up in `expr_vars`.

  Inputs
    * `expr_vars`
      * Named array
      * Contains key-value pairs that will be used to normlize {variables}.
      * See `Normalize Expression` for details.
    * `fields`
      * Optional array
      * If specified, only the listed fields will be normalized. Defaults to all
        fields.
  */

  Macro "norm_expr" (expr_vars, fields) do

    if expr_vars = null then Throw("norm_expr: 'expr_vars' not provided")
    if fields = null then fields = self.colnames()

    for field in fields do
      if !self.in(field, self.colnames())
        then Throw("norm_expr: field '" + field + "' not found in data frame")

      self.tbl.(field) = RunMacro(
        "Normalize Expression", self.tbl.(field), expr_vars
      )
    end

    self.check()
  EndItem

  /*doc
  Sums a column, vector, or array.
  
  Inputs
    * `to_sum`
      * String or vector/array of numerics
      * If string, assumed to be a column name in the data frame.
      
  Returns
    A single numeric that is the sum of `to_sum`
  */
  
  Macro "sum" (to_sum) do
  
    // Argument checking
    if TypeOf(to_sum) = null then Throw("sum: 'to_sum' not provided")
    if !self.in(TypeOf(to_sum), {"string", "array", "vector"})
      then Throw("sum: 'to_sum' must be a string, array, or vector")
    if TypeOf(to_sum) = "array" then to_sum = A2V(to_sum)
    if TypeOf(to_sum) = "string" then do
      colnames = self.colnames()
      if !self.in(to_sum, colnames) 
        then Throw("sum: '" + to_sum + "' not a column name in the data frame")
      to_sum = self.tbl.(to_sum)
    end
    
    sum = VectorStatistic(to_sum, "sum", )
    return(sum)
  EndItem

  /*doc
  This macro creates a outer join function. 
  
  Inputs
    * `slave_tbl`
      * Table to be joined
    * m_id, s_id
      * string of join fields
      
  Returns
    A new df which contains all records in both dataframes
  */

  Macro "outer_join" (slave_tbl, m_id, s_id) do

    // Argument check
    self.check()
    slave_tbl.check()
    if s_id = null then s_id = m_id

    // Check that master and slave fields are present in the table
    colnames = self.colnames()
    if !self.in(m_id, colnames) then Throw(
      "left_join: master field '" + field + "' not found in master table"
      )

    colnames = slave_tbl.colnames()
    if !self.in(s_id, colnames) then Throw(
      "left_join: slave field '" + field + "' not found in slave table"
      )


    jv1 = self.copy()
    jv1.left_join(slave_tbl, m_id, s_id)
    jv1.select(m_id)

    jv2 = slave_tbl.copy()
    jv2.left_join(self, m_id, s_id)
    jv2.select(m_id)

    jv1.bind_rows(jv2)
    v_id = jv1.get_col(m_id)
    arr_id = V2A(v_id)
    new_arr = SortArray(arr_id, {{"Unique","True"}}) 
    new_df = CreateObject("df")
    new_df.mutate(m_id, new_arr)
    
    new_df.left_join(self, m_id, m_id)
    new_df.left_join(slave_tbl, m_id, s_id)
    
    jv1 = null
    jv2 = null
    return(new_df)
  EndItem

endClass
