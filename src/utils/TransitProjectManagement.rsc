/*
Library of tools to create scenario RTS files by extracting from a master
layer and moving to a scenario network.

General approach and notes:
Every route system (RTS) has a stops dbd file. It ends with "S.dbd".
Opening it gives every piece of information needed to use TransCADs
"Create Route from Table" batch macro.

Select from this layer based on project ID.
Export this selection to a new bin file.
Format the new table to look like what is required by the creation macro
  hover over it and hit F1 for help, which shows the table needed
  Includes creating a new field called Node_ID
Loop over each row to get the nearest node from the new layer.
  Log where stops don't have a scenario node nearby.
Place this value into Node_ID.
Run the create-from-table batch macro.
  Compare distance to previous route to check for large deviations.
*/

Macro "test tpm"

  RunMacro("Close All")

  opts = null
  opts.master_rts = "C:\\projects\\TRM\\repo_trmg2\\master\\networks\\master_routes.rts"
  opts.scen_hwy = "C:\\Users\\Kyle\\Desktop\\scratch\\scen\\scenario_links.dbd"
  opts.proj_list = "C:\\Users\\Kyle\\Desktop\\scratch\\scen\\TransitProjectList.csv"
  opts.centroid_qry = "Centroid = 1"
  opts.link_qry = "HCMType <> null"
  opts.output_rts_file = "test.rts"
  opts.delete_shape_stops = "true"
  RunMacro("Transit Project Management", opts)

  ShowMessage("Done")
EndMacro

/*
Inputs
  MacroOpts
    Named array containing all function arguments

    master_rts
      String
      Full path to the master RTS file
      The RTS file must have a field called ProjID that contains values matching
      the proj_list CSV file.

    scen_hwy
      String
      Full path to the scenario roadway dbd that will have the routes loaded.

    centroid_qry
      String
      Query that defines centroids in the node layer. Centroids will be
      prevented from having stops tagged to them. Routes will also be prevented
      from traveleing through them.

    link_qry
      Optional string
      A selection set of links that routes can use. By default, all links can
      be used.

    proj_list
      String
      Full path to the CSV file containing the list of routes to include

    delete_shape_stops
      Boolean (default true)
      Whether or not to remove shape stops after transferring routes. Should
      be true when creating scenario networks. Setting it to false is helpful
      when transferring master routes to a new link layer.

    output_rts_file
      Optional String
      The file name desired for the output route system.
      Defaults to "ScenarioRoutes.rts".
      Do not include the full path. The route system will always be created
      in the same folder as the scenario roadway file.

Outputs
  Creates a new RTS file in the same folder as scen_hwy
*/

Macro "Transit Project Management" (MacroOpts)

  // To prevent potential problems with view names, open files, etc.
  // close everything before starting.
  RunMacro("Close All")

  // Argument extraction
  master_rts = MacroOpts.master_rts
  scen_hwy = MacroOpts.scen_hwy
  proj_list = MacroOpts.proj_list
  centroid_qry = MacroOpts.centroid_qry
  link_qry = MacroOpts.link_qry
  output_rts_file = MacroOpts.output_rts_file
  delete_shape_stops = MacroOpts.delete_shape_stops

  // Argument checking
  if master_rts = null then Throw("'master_rts' not provided")
  if scen_hwy = null then Throw("'scen_hwy' not provided")
  if proj_list = null then Throw("'proj_list' not provided")
  if centroid_qry = null then Throw("'centroid_qry' not provided")
  centroid_qry = RunMacro("Normalize Query", centroid_qry)
  link_qry = RunMacro("Normalize Query", link_qry)
  if output_rts_file = null then output_rts_file = "ScenarioRoutes.rts"
  if delete_shape_stops = null then delete_shape_stops = "true"

  // Set the output directory to be the same as the scenario roadway
  a_path = SplitPath(scen_hwy)
  out_dir = a_path[1] + a_path[2]
  out_dir = RunMacro("Normalize Path", out_dir)
  output_rts_file = out_dir + "\\" + output_rts_file

  // The steps below will tweak the master route system so that it shows up
  // as changed in a git diff. Make a temp copy to avoid this.
  temp_dir = GetTempPath()
  {temp_rts, } = RunMacro("Copy RTS Files", {
    from_rts: master_rts,
    to_dir: temp_dir,
    include_hwy_files: true
  })
  master_rts = temp_rts

  // Update the values of MacroOpts
  MacroOpts.master_rts = master_rts
  MacroOpts.output_rts_file = output_rts_file
  MacroOpts.centroid_qry = centroid_qry
  MacroOpts.link_qry = link_qry
  MacroOpts.out_dir = out_dir
  MacroOpts.delete_shape_stops = delete_shape_stops

  RunMacro("Export to GTFS", MacroOpts)
  RunMacro("Import from GTFS", MacroOpts) 
  RunMacro("Update Scenario Attributes", MacroOpts)
  RunMacro("Check Scenario Route System", MacroOpts)
  if delete_shape_stops then RunMacro("Remove Shape Stops", MacroOpts)
EndMacro

/*

*/

Macro "Export to GTFS" (MacroOpts)

  master_rts = MacroOpts.master_rts
  proj_list = MacroOpts.proj_list

  // Get project IDs from the project list
  proj = OpenTable("projects", "CSV", {proj_list, })
  proj_tbl = CreateObject("Table", proj_list)
  v_pid = proj_tbl.ProjID
  if TypeOf(v_pid) = "null" then Throw("No transit project IDs found")
  if TypeOf(v_pid[1]) <> "string" then v_pid = String(v_pid)

  // Convert the project IDs into route IDs
  opts = null
  opts.rts_file = master_rts
  opts.v_pid = v_pid
  {v_rid, } = RunMacro("Convert ProjID to RouteID", opts)

  // Select routes based on route ids
  map = CreateObject("Map", master_rts)
  {nlyr, llyr, rlyr, slyr} = map.GetLayerNames()
  SetLayer(rlyr)
  export_set = CreateSet("to export")
  n_prev = 0
  for i = 1 to v_rid.length do
    rid = v_rid[i]
    rid = if TypeOf(rid) = "string" then "'" + rid + "'" else String(rid)
    qry = "Select * where Route_ID = " + rid
    operation = if i = 1 then "several" else "more"
    n = SelectByQuery(export_set, operation, qry)
    if n <= n_prev then Throw(T(
      "Transit Manager: Project %s in the project list was not found in the " +
      "master route system.", 
      {v_pid[i]}
    ))
    n_prev = n
  end

  // Basics
  gtfs = CreateObject("GTFS Exporter", {
    RouteFile: "C:\\projects\\TRM\\repo_trmg2\\master\\networks\\master_routes.rts",
    RouteSet: export_set,
    GTFSDirectory: "C:\\Users\\Kyle\\Desktop\\scratch\\gtfs_test"
  })
  gtfs.Export()

endmacro

/*

*/

Macro "Import from GTFS" (MacroOpts)

  scen_hwy = MacroOpts.scen_hwy
  master_rts = MacroOpts.master_rts
  output_rts_file = MacroOpts.output_rts_file
  link_qry = MacroOpts.link_qry
  delete_shape_stops = MacroOpts.delete_shape_stops
  
  // Create a network of the links to use
  // TODO: the GTFS importer can use different networks for different
  // modes, so we could have a rail network or a brt network
  // that only those modes would use. This may not be necessary given the
  // importer already uses the route alignment, though.
  net_file = RunMacro("Create Simple Roadway Net", {
    hwy_dbd: scen_hwy,
    link_qry: link_qry
  })

  gtfs = CreateObject("GTFS Importer", {
    RoadDatabase: scen_hwy,
    GTFSDirectory: "C:\\Users\\Kyle\\Desktop\\scratch\\gtfs_test",
    RouteFile: output_rts_file,
    NetworkFile: net_file
  })
  gtfs.ServicesFlag = 0
  gtfs.Import({DropPhysicalStops: true})

  // Create map with both route systems
  map = CreateObject("Map", output_rts_file)
  {nlyr, llyr, rlyr, slyr} = map.GetLayerNames()
  {master_rlyr, master_slyr, , } = map.AddRouteLayers({RouteFile: master_rts})

  // Clean up route attributes
  tbl = CreateObject("Table", rlyr)
  tbl.Route_Name = tbl.[Short Name]
  ReloadRouteSystem(output_rts_file)
  tbl.RenameField({FieldName: "Route", NewName: "Master_Route_ID"})
  tbl.ChangeField({
    FieldName: "Master_Route_ID",
    Description: "Route ID from the master route system"
  })
  tbl.DropFields({FieldNames: {
    "Mode",
    "Short Name",
    "Long Name",
    "Description",
    "URL",
    "Color",
    "Text Color",
    "Trip",
    "Sign",
    "Service",
    "Agency Name",
    "Agency URL",
    "Agency Phone",
    "Direction",
    "M", "Tu", "W", "Th", "F", "Sa", "Su",
    "ScheduleStartTime",
    "ScheduleEndTime",
    "AM", "Midday", "PM", "Night",
    "Start Time", "End Time",
    "Headway"
  }})

  // Add back route attributes from the master route system
  fields = {
    {FieldName: "ProjID", Type: "string"},
    {FieldName: "Mode", Type: "integer"},
    {FieldName: "Fare", Type: "real"},
    {FieldName: "AMHeadway", Type: "integer"},
    {FieldName: "MDHeadway", Type: "integer"},
    {FieldName: "PMHeadway", Type: "integer"},
    {FieldName: "NTHeadway", Type: "integer"}
  }
  tbl.AddFields({Fields: fields})
  master_tbl = CreateObject("Table", master_rlyr)
  join_tbl = tbl.Join({
    Table: master_tbl,
    LeftFields: "Master_Route_ID",
    RightFields: "Route_ID"
  })
  join_tbl.(rlyr + ".ProjID") = join_tbl.(master_rlyr + ".ProjID")
  join_tbl.(rlyr + ".Mode") = join_tbl.(master_rlyr + ".Mode")
  join_tbl.(rlyr + ".Fare") = join_tbl.(master_rlyr + ".Fare")
  join_tbl.(rlyr + ".AMHeadway") = join_tbl.(master_rlyr + ".AMHeadway")
  join_tbl.(rlyr + ".MDHeadway") = join_tbl.(master_rlyr + ".MDHeadway")
  join_tbl.(rlyr + ".PMHeadway") = join_tbl.(master_rlyr + ".PMHeadway")
  join_tbl.(rlyr + ".NTHeadway") = join_tbl.(master_rlyr + ".NTHeadway")

  // Clean up stop attributes
  stop_tbl = CreateObject("Table", slyr)
  stop_tbl.DropFields({FieldNames: {
    "Pickup",
    "Dropoff",
    "Service",
    "Length",
    "Sequence"
  }})
  // Add back stop attributes from master
  fields = {
    {FieldName: "shape_stop", Type: "integer"},
    {FieldName: "dwell_on", Type: "real"},
    {FieldName: "dwell_off", Type: "real"},
    {FieldName: "xfer_pen", Type: "real"}
  }
  stop_tbl.AddFields({Fields: fields})
  stop_tbl.RenameField({FieldName: "GTFS_Stop_ID", NewName:"Master_Stop_ID"})
  master_tbl = CreateObject("Table", master_slyr)
  join_tbl = stop_tbl.Join({
    Table: master_tbl,
    LeftFields: "Master_Stop_ID",
    RightFields: "ID"
  })
  join_tbl.(slyr + ".shape_stop") = join_tbl.(master_slyr + ".shape_stop")
  join_tbl.(slyr + ".dwell_on") = join_tbl.(master_slyr + ".dwell_on")
  join_tbl.(slyr + ".dwell_off") = join_tbl.(master_slyr + ".dwell_off")
  join_tbl.(slyr + ".xfer_pen") = join_tbl.(master_slyr + ".xfer_pen")
  join_tbl = null
endmacro

/*
Updates the scenario route system attributes based on the TransitProjectList.csv
Also tags stops with node IDs in the 'node_id' field.
*/

Macro "Update Scenario Attributes" (MacroOpts)

  // Argument extraction
  // master_rts = MacroOpts.master_rts
  scen_hwy = MacroOpts.scen_hwy
  proj_list = MacroOpts.proj_list
  // centroid_qry = MacroOpts.centroid_qry
  output_rts_file = MacroOpts.output_rts_file

  // Read in the parameter file
  param = CreateObject("df")
  param.read_csv(proj_list)

  // Create a map of the scenario RTS
  opts = null
  opts.file = output_rts_file
  {map, {rlyr, slyr}} = RunMacro("Create Map", opts)
  SetLayer(rlyr)

  // Loop over column names and update attributes. ProjID is skipped.
  a_colnames = param.colnames()
  // Only do this process if columns other than ProjID exist.
  if a_colnames.length > 1 then do
    for col_name in a_colnames do
      if col_name = "ProjID" then continue

      // Create a data frame that filters out null values from this column
      temp = param.copy()
      temp.filter(col_name + " <> null")

      // Break if this column is empty
      test = temp.is_empty()
      if temp.is_empty() then continue

      {v_pid, v_value} = temp.get_col({"ProjID", col_name})
      for i = 1 to v_pid.length do
        pid = v_pid[i]
        value = v_value[i]

        // Locate the route with this project ID. If not found, throw an error.
        opts = null
        opts.Exact = "true"
        rh = LocateRecord(rlyr + "|", "ProjID", {String(pid)}, opts)
        if rh = null then do
          pid_string = if TypeOf(pid) = "string" then pid else String(pid)
          Throw("ProjID '" + pid_string + "' not found in route layer")
        end

        // Update the attribute
        SetRecord(rlyr, rh)
        rlyr.(col_name) = value
      end
    end
  end

  // Tag stops to nodes within
  a_field = {{"Node_ID", "Integer", 10, , , , , "ID of node closest to stop"}}
  RunMacro("Add Fields", {view: slyr, a_fields: a_field})
  n = TagRouteStopsWithNode(rlyr,,"Node_ID",.2)

  CloseMap(map)
EndMacro

/*
Creates a CSV with stats on how well the route system transfer did
*/

Macro "Check Scenario Route System" (MacroOpts)

  // Argument extraction
  master_rts = MacroOpts.master_rts
  scen_hwy = MacroOpts.scen_hwy
  proj_list = MacroOpts.proj_list
  centroid_qry = MacroOpts.centroid_qry
  output_rts_file = MacroOpts.output_rts_file
  out_dir = MacroOpts.out_dir

  // Create path to the copy of the master rts and roadway files
  {drive, path, filename, ext} = SplitPath(master_rts)
  opts = null
  opts.rts_file = master_rts
  master_hwy_copy = RunMacro("Get RTS Roadway File", opts)

  // Get project IDs from the project list and convert to route ids on both
  // the master and scenario route systems.
  proj = OpenTable("projects", "CSV", {proj_list, })
  v_pid = GetDataVector(proj + "|", "ProjID", )
  if TypeOf(v_pid) = "null" then Throw("No transit project IDs found")
  if TypeOf(v_pid[1]) <> "string" then v_pid = String(v_pid)
  CloseView(proj)
  opts = null
  opts.rts_file = master_rts
  opts.v_pid = v_pid
  {v_rid_m, v_rev_pid} = RunMacro("Convert ProjID to RouteID", opts)
  opts.rts_file = output_rts_file
  {v_rid_s, } = RunMacro("Convert ProjID to RouteID", opts)

  // Summarize the number of missing nodes by route. In order to have
  // all the fields in one table, you have to open the RTS file, which
  // links multiple tables together.
  opts = null
  opts.file = master_rts
  {master_map, {rlyr_m, slyr_m, , , llyr_m}} = RunMacro("Create Map", opts)
  stops_df = CreateObject("df")
  opts = null
  opts.view = slyr_m
  // opts.fields = {"Route_ID", "missing_node"}
  opts.fields = {"Route_ID"}
  stops_df.read_view(opts)
  stops_df.mutate("missing_node", null)
  stops_df.group_by("Route_ID")
  stops_df.summarize("missing_node", "sum")
  stops_df.rename("sum_missing_node", "missing_node")

  // Open the scenario route system in a separate map.
  opts = null
  opts.file = output_rts_file
  opts.debug = 1
  {scen_map, {rlyr_s, slyr_s, , , llyr_s}} = RunMacro("Create Map", opts)
  // Compare route lengths between master and scenario
  data = null

  for i = 1 to v_rev_pid.length do
    pid = v_rev_pid[i]
    rid_m = v_rid_m[i]
    rid_s = v_rid_s[i]

    // Calculate the route length in the master rts
    opts = null
    opts.rlyr = rlyr_m
    opts.llyr = llyr_m
    opts.lookup_field = "Route_ID"
    opts.id = rid_m
    {length_m, num_stops_m} = RunMacro("Get Route Length and Stops", opts)
    // Calculate the route length in the scenario rts
    opts = null
    opts.rlyr = rlyr_s
    opts.llyr = llyr_s
    opts.lookup_field = "Route_ID"
    opts.id = rid_s
    {length_s, num_stops_s} = RunMacro("Get Route Length and Stops", opts)

    // calculate difference and percent difference
    diff = length_s - length_m
    pct_diff = round(diff / length_m * 100, 2)

    // store this information in a named array
    data.projid = data.projid + {pid}
    data.master_route_id = data.master_route_id + {rid_m}
    data.scenario_route_id = data.scenario_route_id + {rid_s}
    data.master_length = data.master_length + {length_m}
    data.scenario_length = data.scenario_length + {length_s}
    data.length_diff = data.length_diff + {diff}
    data.pct_diff = data.pct_diff + {pct_diff}
    data.master_stops = data.master_stops + {num_stops_m}
    data.scenario_stops = data.scenario_stops + {num_stops_s}
    data.missing_stops = data.missing_stops + {num_stops_m - num_stops_s}
  end

  // Close both maps
  CloseMap(master_map)
  CloseMap(scen_map)

  // Convert the named array into a data frame
  length_df = CreateObject("df", data)
  
  length_df.write_csv(out_dir + "/_rts_creation_results.csv")

  RunMacro("Close All")
EndMacro

/*
Helper macro used to convert project IDs (which are on the route layer) to
route IDs (which are included on the node and link tables of the route layer).

Inputs
  MacroOpts
    Named array that holds arguments (e.g. MacroOpts.master_rts)

    rts_file
      String
      Full path to the .rts file that contains both route and project IDs

    v_pid
      Array or vector of unique project IDs.

Returns
  An array of two vectors
  A vector of route IDs corresponding to the input project IDs.
  A revised vector of project IDs. If Project IDs are associated with more
    than one route, the project ID will be repeated in this vector.
*/

Macro "Convert ProjID to RouteID" (MacroOpts)

  // Argument extraction
  rts_file = MacroOpts.rts_file
  v_pid = MacroOpts.v_pid

  // Check that the project IDs are unique
  opts = null
  opts.Unique = "true"
  v_unique = SortVector(v_pid, opts)
  if v_pid.length <> v_unique.length then Throw(
    "'v_pid' must be a vector of unique values"
  )

  // Create map of RTS
  opts = null
  opts.file = rts_file
  {map, {rlyr, slyr, phlyr}} = RunMacro("Create Map", opts)

  // Create an error file that will list any project IDs not found in the
  // route system.
  num_notfound = 0
  {drive, path, , } = SplitPath(rts_file)
  error_file = drive + path + "TransitBuildingError.csv"
  file = OpenFile(error_file, "w")
  WriteLine(file, "Below projects are missing:")

  // Convert project IDs into route IDs
  SetLayer(rlyr)
  route_set = "scenario routes"
  for i = 1 to v_pid.length do
    id = v_pid[i]

    // Select routes that match the current project id
    type = TypeOf(id)
    id2 = if type = "string" then "'" + id + "'" else String(id)
    qry = "Select * where ProjID = " + id2
    operation = if i = 1 then "several" else "more"
    n = SelectByQuery(route_set, operation, qry)
    if n = n_prev then do
      num_notfound = num_notfound + 1
      if type = "string"
        then WriteLine(file, id)
        else WriteLine(file, String(id))
    end

    n_prev = n
  end

  CloseFile(file)
  if num_notfound > 0 then Throw(
    "Projects not found in the master route system. See error log in the scenario folder."
  )
  //remove error log once scenario created successfully
  if num_notfound = 0 and GetFileInfo(error_file) <> null then DeleteFile(error_file)

  // Get final results
  v_rid = GetDataVector(rlyr + "|" + route_set, "Route_ID", )
  v_rev_pid = GetDataVector(rlyr + "|" + route_set, "ProjID", )

  CloseMap(map)
  return({v_rid, v_rev_pid})
EndMacro

/*
Helper function for "Check Scenario Route System".
Determines the length of the links that make up a route and number of stops.
If this ends being used by multiple macros in different scripts, move it
to the ModelUtilities.rsc file.

MacroOpts
  Named array that holds other arguments (e.g. MacroOpts.rlyr)

  rlyr
    String
    Name of route layer

  llyr
    String
    Name of the link layer

  lookup_field
    String
    Field to search for the given ID

  id
    String or Integer
    ID to look for in lookup_field

Returns
  Array of two items
    * Length of route
    * Number of stops on route
*/

Macro "Get Route Length and Stops" (MacroOpts)

  // Argument extraction
  rlyr = MacroOpts.rlyr
  llyr = MacroOpts.llyr
  lookup_field = MacroOpts.lookup_field
  id = MacroOpts.id

  // Determine the current layer before doing work to set it back after the
  // macro finishes.
  cur_layer = GetLayer()

  // Get route name based on the lookup_field and id given
  SetLayer(rlyr)
  opts = null
  opts.Exact = "true"
  rh = LocateRecord(rlyr + "|", lookup_field, {id}, opts)
  if rh = null then Throw("Value not found in" + lookup_field)
  SetRecord(rlyr, rh)
  route_name = rlyr.Route_Name
  a_stops = GetRouteStops(rlyr, route_name, )
  num_stops = a_stops.length

  // Get IDs of links that the route runs on
  a_links = GetRouteLinks(rlyr, route_name)
  for link in a_links do
    a_lid = a_lid + {link[1]}
  end

  // Determine length of those links
  SetLayer(llyr)
  n = SelectByIDs("route_links", "several", a_lid, )
  if n = 0 then Throw("Route links not found in layer '" + llyr + "'")
  v_length = GetDataVector(llyr + "|route_links", "Length", )
  length = VectorStatistic(v_length, "Sum", )

  // Set the layer back to the original if there was one.
  if cur_layer <> null then SetLayer(cur_layer)

  return({length, num_stops})
EndMacro

/*

*/

Macro "Remove Shape Stops" (MacroOpts)

  output_rts_file = MacroOpts.output_rts_file
  
  map = CreateObject("Map", output_rts_file)
  {nlyr, llyr, rlyr, slyr} = map.GetLayerNames()
  stop_tbl = CreateObject("Table", slyr)
  stop_fields = stop_tbl.GetFieldNames()
  if delete_shape_stops and stop_fields.position("shape_stop") <> 0 then do
    n = stop_tbl.SelectByQuery({
      SetName: "to remove",
      Query: "shape_stop = 1",
      Operation: "several"
    })
    if n > 0 then do
      SetLayer(stop_tbl.GetView())
      DeleteRecordsInSet("to remove")
    end
  end

endmacro