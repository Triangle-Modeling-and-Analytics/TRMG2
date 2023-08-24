/*
Note: Could flesh this out into a general macro that can be called from
the drop down menu of tools.
*/

macro "sort project groups"
  llyr = GetLayer()
  master_dbd = GetLayerDB(llyr)
  fix_master = RunMacro("Check Project Group Validity", llyr)
  if fix_master then do
    RunMacro("Clean Project Groups", master_dbd)
    ShowMessage("Project groups fixed.")
  end
endmacro

/*
A function to manage scenario network creation from a master roadway database.

Inputs (all in a named array)
  * `hwy_dbd`
    * String
    * Full path to roadway network to update
  * `proj_list`
    * String
    * CSV file of project IDs. Must contain a single column titled "ProjID" with
      a proj ID on each row.
  * `master_dbd`
    * String
    * Full path to master roadway network to be cleaned (if necessary)

Returns  
Nothing. Destructively modifies `hwy_dbd` by changing the base attributes with
the project attributes.
*/

Macro "Roadway Project Management" (MacroOpts)

  hwy_dbd = MacroOpts.hwy_dbd
  proj_list = MacroOpts.proj_list
  master_dbd = MacroOpts.master_dbd

  // Argument check
  if hwy_dbd = null then Throw("'hwy_dbd' not provided")
  if proj_list = null then Throw("'proj_list' not provided")
  if master_dbd = null then Throw("'master_dbd' not provided")

  // Get vector of project IDs from the project list file
  // gplyr's read functions won't work here until it can handle empty files.
  csv_tbl = OpenTable("tbl", "CSV", {proj_list, })
  v_projIDs = GetDataVector(csv_tbl + "|", "ProjID", )
  CloseView(csv_tbl)
  DeleteFile(Substitute(proj_list, ".csv", ".DCC", ))

  // Open the roadway dbd
  {nlyr, llyr} = GetDBLayers(hwy_dbd)
  llyr = AddLayerToWorkspace(llyr, hwy_dbd, llyr)
  nlyr = AddLayerToWorkspace(nlyr, hwy_dbd, nlyr)
  {llyr_f_names, llyr_f_specs} = RunMacro("Get Fields", {view_name: llyr})

  // Check validity of project definitions
  fix_master = RunMacro("Check Project Group Validity", llyr)
  if fix_master then do
    RunMacro("Clean Project Groups", master_dbd)
    Throw("Project groups fixed. Start the export process again.")
  end
  missing_projects = RunMacro("Check for Missing Projects", v_projIDs, llyr, hwy_dbd)

  // Determine the project groupings and attributes on the link layer.
  // Remove ID from the list of attributes to update.
  projGroups = RunMacro("Get Project Groups", llyr)
  attrList = RunMacro("Get Project Attributes", llyr)
  attrList = ExcludeArrayElements(attrList, 1, 1)

  // Loop over each project ID  
  for p = v_projIDs.length to 1 step -1 do
    projID = v_projIDs[p]
    type = TypeOf(projID)
    proj_found = 0

    // Add "UpdatedWithP" field
    if p = v_projIDs.length then do
      type2 = if CompareStrings(type, "string", ) then "Character" else "Integer"
      a_fields = {{"UpdatedWithP", type2, 16, }}
      RunMacro("Add Fields", {view: llyr, a_fields: a_fields})
    end

    // Loop over each project group (group of project fields)
    for g = 1 to projGroups.length do
      pgroup = projGroups[g]

      // Search for the ID in the current group.  Update attributes if found.
      // Do not update if the UpdatedWithP field is already marked with a 1.
      SetLayer(llyr)
      // Handle possibility of string or integer IDs
      if TypeOf(projID) <> "string" then
        qry = "Select * where " + pgroup + "ID = " + String(projID)
        else qry = "Select * where " + pgroup + "ID = '" + projID + "'"
      qry = qry + " and UpdatedWithP = null"
      n = SelectByQuery("updateLinks", "Several", qry)
      if n > 0 then do

        // Loop over each field to update
        for f = 1 to attrList.length do
          baseField = attrList[f]
          projField = pgroup + attrList[f]

          v_vec = GetDataVector(llyr + "|updateLinks", projField, )
          SetDataVector(llyr + "|updateLinks", baseField, v_vec, )
        end

        // Mark the UpdatedWithP field to prevent these links from being
        // updated again in subsequent loops.
        opts = null
        opts.Constant = projID
        if TypeOf(projID) = "string" then do
          v_vec = Vector(v_vec.length, "String", opts)
        end else do
          v_vec = Vector(v_vec.length, "Long", opts)
        end
        SetDataVector(llyr + "|updateLinks", "UpdatedWithP", v_vec, )
      end
    end
  end

  // Delete links with -99 in any project-related attribute.
  // DeleteRecordsInSet() and DeleteLink() are both slow.
  // Re-export instead.
  SetLayer(llyr)
  for f = 1 to attrList.length do
    field = attrList[f]
    if f = 1 then qtype = "several" else qtype = "more"

    spec = llyr_f_specs.(field)
    {field_type, , } = GetFieldInfo(spec)
    if field_type = "String"
      then query = "Select * where " + field + " = '-99'"
      else query = "Select * where " + field + " = -99"
    to_del = SelectByQuery("to delete", qtype, query)
  end  
  if to_del > 0 then do
    to_exp = SetInvert("to export", "to delete")    
    if to_exp = 0 then Throw("No links have attributes")
    a_path = SplitPath(hwy_dbd)
    new_dbd = a_path[1] + a_path[2] + a_path[3] + "_temp" + a_path[4]
    {l_names, l_specs} = GetFields(llyr, "All")
    {n_names, n_specs} = GetFields(nlyr, "All")
    opts = null
    opts.[Field Spec] = l_specs
    opts.[Node Name] = nlyr
    opts.[Node Field Spec] = n_specs
    ExportGeography(llyr + "|to export", new_dbd, opts)
    DropLayerFromWorkspace(llyr)
    DropLayerFromWorkspace(nlyr)
    CopyDatabase(new_dbd, hwy_dbd)
    DeleteDatabase(new_dbd)
  end
EndMacro

/*
Determines the number of project groups on a network
Assumes groups defined by fields like "p1ID", "p2ID",
"p10ID", etc. (up to "p99ID")

Returns
  projGroups
  Array of project prefixes
*/

Macro "Get Project Groups" (llyr)

  a_fields = GetFields(llyr, "All")
  a_fields = a_fields[1]
  projGroups = null
  for f = 1 to a_fields.length do
    field = a_fields[f]

    length = StringLength(field)
    if field[1] = "p" & length <= 5  &
      SubString(field, length - 1, 2) = "ID"
      then projGroups = projGroups + {Substitute(field, "ID", "", )}
  end

  return(projGroups)
EndMacro

/*
Gets an array of attributes associated with projects
*/

Macro "Get Project Attributes" (llyr)

  projGroups = RunMacro("Get Project Groups", llyr)
  pgroup = projGroups[1]

  a_fields = GetFields(llyr, "All")
  a_fields = a_fields[1]
  attr = null
  for f = 1 to a_fields.length do
    field = a_fields[f]

    if Substring(field, 1, 2) = pgroup then do
      len = StringLength(field)
      field = Substring(field, 3, len - 2)
      attr = attr + {field}
    end
  end

  return(attr)
EndMacro

/*
Given a single project ID, returns which group the project is in
*/

Macro "Get Project's Group" (p_id, llyr)

  // Determine the project groupings on the link layer
  projGroups = RunMacro("Get Project Groups", llyr)

  SetLayer(llyr)
  qry_id = if (TypeOf(p_id) = "string")
    then "'" + p_id + "'"
    else String(p_id)

  for p = 1 to projGroups.length do
    pgroup = projGroups[p]

    qry = "Select * where " + pgroup + "ID = " + qry_id
    n = SelectByQuery("find group", "several", qry)
    if n > 0 then do
      DeleteSet("find group")
      return(pgroup)
    end
  end

  Throw("Project " + qry_id + " not found")
EndMacro

/*
Makes sure that project IDs only show up in one group
*/

Macro "Check Project Group Validity" (llyr)

  // Determine the project groupings on the link layer
  projGroups = RunMacro("Get Project Groups", llyr)

  // return if only 1 project group
  if projGroups.length = 1 then return()

  // Create a named array
  DATA = null
  for p = 1 to projGroups.length do
    pgroup = projGroups[p]

    // Collect unique vector of IDs in current group
    v_id = GetDataVector(llyr + "|", pgroup + "ID", )
    opts = null
    opts.[Omit Missing] = "True"
    opts.Unique = "True"
    v_id = SortVector(v_id, opts)

    // Set it in named array
    DATA.(pgroup) = v_id
  end

  for p = 1 to projGroups.length do
    pgroup = projGroups[p]

    // create array of other project groups
    pos = ArrayPosition(projGroups, {pgroup}, )
    a_other_groups = ExcludeArrayElements(projGroups, pos, 1)

    // loop over each ID in the current pgroup
    v_id = DATA.(pgroup)
    for i = 1 to v_id.length do
      id = v_id[i]

      // search other groups for current ID
      for o = 1 to a_other_groups.length do
        ogroup = a_other_groups[o]

        if ArrayPosition(V2A(DATA.(ogroup)), {id}, ) then do
          str_id = if (TypeOf(id) = "string")
            then "'" + id + "'"
            else "'" + String(id) + "'"
          opts = null
          opts.Buttons = "YesNo"
          yesno = MessageBox(
            "Project " + str_id + " was found in multiple project groups.\n" +
            "Do you want to run the cleaning macro on the master network?",
            opts
          )
          if yesno = "Yes" then do
            return("True")
          end else Throw("Cannot continue until the master network is cleaned.")
        end
      end
    end
  end
EndMacro

/*
This macro makes sure that projects are are completely contained within the
same group in the master network.  It also makes sure that the group is as low
a number as possible.
*/

Macro "Clean Project Groups" (master_dbd)

  // Add link layer to workspace
  {nlyr, llyr} = GetDBLayers(master_dbd)
  llyr = AddLayerToWorkspace(llyr, master_dbd, llyr)

  // Determine the project groupings and attributes on the link layer
  projGroups = RunMacro("Get Project Groups", llyr)
  attrList = RunMacro("Get Project Attributes", llyr)

  v_ids = RunMacro("Get All Project IDs", llyr)
  for i = 1 to v_ids.length do
    id = v_ids[i]

    qry_id = if (TypeOf(id) = "string")
      then "'" + id  + "'"
      else String(id)

    // Check how many project groups the project is in
    // while creating a selection set of all project links

    {set_name, num_records, num_pgroups} =
      RunMacro("Create Project Set", id, llyr)

    // if multiple groups were found, clean up
    if num_pgroups > 1 then do
      // find first project group where all project attributes can exist
      target_group = null
      for p = 1 to projGroups.length do
        pgroup = projGroups[p]

        v_test = GetDataVector(llyr + "|" + set_name, pgroup + "ID", )
        opts = null
        opts.[Omit Missing] = "True"
        opts.Unique = "True"
        v_test = SortVector(v_test, opts)
        if v_test.length = 0 or (v_test.length = 1 and v_test[1] = id) then target_group = pgroup
      end

      // if none found, create a new group
      if target_group = null then do
        RunMacro("Create Project Group", p, llyr)
        target_group = "p" + String(p)
      end

      // Move project to target group
      RunMacro("Move Project To Group", id, target_group, llyr)
    end
  end

  // After moving all project attributes into the same group, shift projects into
  // lower groups until no more shifts can be made.
  changed = "True"
  while changed do
    changed = "False"

    for i = 1 to v_ids.length do
      id = v_ids[i]

      // Select the project links
      pgroup = RunMacro("Get Project's Group", id, llyr)
      qry_id = if (TypeOf(id) = "string")
        then "'" + id + "'"
        else String(id)
      qry = "Select * where " + pgroup + "ID = " + qry_id
      n = SelectByQuery("proj_links", "several", qry)

      // If the project is not in the lowest project group, check to
      // see if it can be moved into a lower group.
      pos = ArrayPosition(projGroups, {pgroup}, )
      if pos > 1 then do
        for p = 1 to pos - 1 do
          target_group = projGroups[p]

          opts = null
          opts.[Source And] = "proj_links"
          qry = "Select * where " + target_group + "ID = null"
          m = SelectByQuery("check", "several", qry, opts)
          if m = n then do
            RunMacro("Move Project To Group", id, target_group, llyr)
            changed = "True"
            p = pos + 1
          end
        end
      end
    end
  end

  // Delete any empty project groups
  RunMacro("Delete Empty Project Groups", llyr)
  RunMacro("Close All")
EndMacro

/*
Creates a selection of all links that belong to a project
regardless of project group.

Returns
  set_name
  Name of selection set (always "proj_links")

  num_records
  Number of records in selection set

  num_pgroups
  Number of groups the project is in
*/

Macro "Create Project Set" (p_id, llyr)

  // Determine the project groupings on the link layer
  projGroups = RunMacro("Get Project Groups", llyr)

  num_pgroups = 0
  set_name = "proj_links"
  qry_id = if (TypeOf(p_id) = "string")
    then "'" + p_id + "'"
    else String(p_id)
  SetLayer(llyr)
  for p = 1 to projGroups.length do
    qry = "Select * where " + projGroups[p] + "ID = " + qry_id
    n = SelectByQuery("test", "several", qry)
    if n > 0 then num_pgroups = num_pgroups + 1
    mode = if (p = 1) then "several" else "more"
    num_records = SelectByQuery(set_name, mode, qry)
  end

  return({set_name, num_records, num_pgroups})
EndMacro

/*
Removes any extra project groups from the network
*/

Macro "Delete Empty Project Groups" (llyr)

  // Determine the project groupings and attributes on the link layer
  projGroups = RunMacro("Get Project Groups", llyr)
  attrList = RunMacro("Get Project Attributes", llyr)

  SetLayer(llyr)
  for p = 1 to projGroups.length do
    pgroup = projGroups[p]

    qry = "Select * where " + pgroup + "ID <> null"
    n = SelectByQuery("sel", "several", qry)
    if nz(n) = 0 then do
      RunMacro("Remove Field", llyr, pgroup + "ID")
      for a = 1 to attrList.length do
        attr = attrList[a]

        field_name = pgroup + attr
        RunMacro("Remove Field", llyr, pgroup + attr)
      end
    end
  end
EndMacro

/*
Gets a list of all project IDs across all groups

Returns
  v_id
  Vector of project IDs
*/

Macro "Get All Project IDs" (llyr)

  // Determine the project groupings and attributes on the link layer
  projGroups = RunMacro("Get Project Groups", llyr)

  for p = 1 to projGroups.length do
    pgroup = projGroups[p]

    a_id = a_id + V2A(GetDataVector(llyr + "|", pgroup + "ID", ))
  end

  opts = null
  opts.[Omit Missing] = "True"
  opts.Unique = "True"
  v_id = SortVector(A2V(a_id), opts)

  return(v_id)
EndMacro

/*
Creates a new group of project fields
*/

Macro "Create Project Group" (number, llyr)

  // Determine the project groupings and attributes on the link layer
  attrList = RunMacro("Get Project Attributes", llyr)

  pgroup = "p" + String(number)
  for f = 1 to attrList.length do
    field = attrList[f]

    // Create a new field that matches the info from the first project group
    {type, width, dec, index} = GetFieldInfo(llyr + ".p1" + field)
    if type = "String" then type = "Character"
    a_fields = {
      {pgroup + field, type, width, dec}
    }
    RunMacro("Add Fields", {view: llyr, a_fields: a_fields})
  end
EndMacro

/*
This macro is called by the "Clean Project Groups" macro. "Clean Project Groups"
creates a selection set of the current project's links called "proj_links",
which is used by this macro.
*/

Macro "Move Project To Group" (p_id, target_group, llyr)

  // Determine the project groupings and attributes on the link layer
  projGroups = RunMacro("Get Project Groups", llyr)
  attrList = RunMacro("Get Project Attributes", llyr)

  SetLayer(llyr)
  qry_id = if (TypeOf(p_id) = "string")
    then "'" + p_id + "'"
    else String(p_id)

  // Check that target group fields are empty for the project links
  opts = null
  opts.[Source And] = "proj_links"
  qry = "Select * where " + target_group + "ID <> null and " +
    target_group + "ID <> " + qry_id
  n = SelectByQuery("mptg_check", "several", qry, opts)
  if n > 0 then Throw("Target group fields are not empty")
  DeleteSet("mptg_check")

  for p = 1 to projGroups.length do
    pgroup = projGroups[p]

    qry = "Select * where " + pgroup + "ID = " + qry_id
    n = SelectByQuery("mptg_sel", "several", qry)
    if n > 0 and pgroup <> target_group then do
      // Move project attributes
      for a = 1 to attrList.length do
        from_field = pgroup + attrList[a]
        to_field = target_group + attrList[a]

        v_vec = GetDataVector(llyr + "|mptg_sel", from_field, )
        v_null = Vector(v_vec.length, v_vec.type, )
        SetDataVector(llyr + "|mptg_sel", to_field, v_vec, )
        SetDataVector(llyr + "|mptg_sel", from_field, v_null, )
      end
    end
  end

  DeleteSet("mptg_sel")
EndMacro

/*
This macro allows you to quickly create a geographic file of just the
project links, which is usful in many mapping applications.

Inputs (all in named array)
  * `hwy_dbd`
    * The line geographic file to export projects from
  * `output_dbd`
    * Optional output file. By default, is placed in same directory as `hwy_dbd`.
  * `project_ids`
    * Optional vector or array of project IDs to include. By default, all 
      projects will be exported.
*/

Macro "Export Project Layer" (MacroOpts)

  hwy_dbd = MacroOpts.hwy_dbd
  output_dbd = MacroOpts.output_dbd
  project_ids = MacroOpts.project_ids

  // Argument checking
  hwy_dbd = RunMacro(
    "check file", {file: hwy_dbd, extension: "dbd", required: 1, must_exist: 1}
  )
  output_dbd = RunMacro("check file", {file: output_dbd, extension: "dbd"})
  if output_dbd = null then do
    {drive, folder, name, ext} = SplitPath(hwy_dbd)
    output_dbd = drive + folder + name + "_projects.dbd"
  end
  project_ids = RunMacro("check array", {array: project_ids})
  
  {map, {nlyr, llyr}} = RunMacro("Create Map", {file: hwy_dbd})
  if project_ids = null then project_ids = RunMacro("Get All Project IDs", llyr)
  {fields, specs} = GetFields(llyr, "All")
  for field in fields do
    merge_fields_array = merge_fields_array + {{field, field}}
  end
  
  for project_id in project_ids do
    {set_name, num_records, num_pgroups} = RunMacro(
      "Create Project Set", project_id, llyr
    )
    if project_id = project_ids[1] then do
      ExportGeography(
        llyr + "|" + set_name, output_dbd,
        {"Field Spec": specs}
      )
      {nlyr_merged, llyr_merged} = GetDBLayers(output_dbd)
      llyr_merged = AddLayer(map, llyr_merged, output_dbd, llyr_merged)
    end else do
      MergeGeography(
        llyr_merged, llyr + "|" + set_name,
        {Fields: merge_fields_array, "Allow Duplicates": "true"}
      )
    end
  end

  CloseMap(map)
endmacro

/*
This checks if there are project IDs in the project list that are not
on the highway link layer.
*/

Macro "Check for Missing Projects" (v_projIDs, llyr, hwy_dbd)
 
  v_all_ids = RunMacro("Get All Project IDs", llyr)
  for pid in v_projIDs do
    if v_all_ids.Position(pid) = 0 then missing = missing + {pid}
  end
  
  {drive, path, , } = SplitPath(hwy_dbd)
  error_file = drive + path + "_missing_roadway_projects.csv"
 
  if missing <> null then do
    file = OpenFile(error_file, "w")
    WriteLine(file, "Below projects are missing:")
    for id in missing do
      if TypeOf(id) <> "string" 
        then string_id = String(id)
        else string_id = id
      WriteLine(file, string_id)
    end
    CloseFile(file)
    return("true")
  end else do
    if GetFileInfo(error_file) <> null then DeleteFile(error_file)
  end
endmacro

/*
TODO: Flesh out into a general macro for the drop down menu.
*/

Macro "run export project layer"
  opts.hwy_dbd = "C:\\projects\\TRM\\trm_project\\repo_trmg2\\master\\networks\\master_network.dbd"
  RunMacro("Export Project Layer", opts)
  ShowMessage("Project layer exported")
endmacro
