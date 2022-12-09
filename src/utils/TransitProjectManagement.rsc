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
  output_rts_file = out_dir + "/" + output_rts_file

  // Update the values of MacroOpts
  MacroOpts.output_rts_file = output_rts_file
  MacroOpts.centroid_qry = centroid_qry
  MacroOpts.link_qry = link_qry
  MacroOpts.out_dir = out_dir
  MacroOpts.delete_shape_stops = delete_shape_stops

  RunMacro("Export to GTFS", MacroOpts)
  RunMacro("Import from GTFS", MacroOpts)
  RunMacro("Update Scenario Attributes", MacroOpts)
  Throw()
  // RunMacro("Check Scenario Route System", MacroOpts)
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
  // TODO: drop physical stops when dev can run successfully
  // gtfs.Import({DropPhysicalStops: true})
  gtfs.Import()

  // Create map with both route systems
  map = CreateObject("Map", output_rts_file)
  {nlyr, llyr, rlyr, slyr} = map.GetLayerNames()
  {master_rlyr, master_slyr, , } = map.AddRouteLayers({RouteFile: master_rts})

  // Clean up route attributes
  tbl = CreateObject("Table", rlyr)
  tbl.Route_Name = tbl.[Short Name]
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

/*
Creates the scenario route system.
*/

Macro "Create Scenario Route System" (MacroOpts)

  // Argument extraction
  master_rts = MacroOpts.master_rts
  scen_hwy = MacroOpts.scen_hwy
  proj_list = MacroOpts.proj_list
  centroid_qry = MacroOpts.centroid_qry
  link_qry = MacroOpts.link_qry
  output_rts_file = MacroOpts.output_rts_file
  out_dir = MacroOpts.out_dir
  delete_shape_stops = MacroOpts.delete_shape_stops

  // Make a copy of the master_rts into the output directory to prevent
  // this macro from modifying the actual master RTS.
  opts = null
  opts.from_rts = master_rts
  opts.to_dir = out_dir
  opts.include_hwy_files = "true"
  {master_rts_copy, master_hwy_copy} = RunMacro("Copy RTS Files", opts)

  // Get project IDs from the project list
  proj = OpenTable("projects", "CSV", {proj_list, })
  v_pid = GetDataVector(proj + "|", "ProjID", )
  if TypeOf(v_pid) = "null" then Throw("No transit project IDs found")
  if TypeOf(v_pid[1]) <> "string" then v_pid = String(v_pid)

  // Convert the project IDs into route IDs
  opts = null
  opts.rts_file = master_rts
  opts.v_pid = v_pid
  {v_rid, } = RunMacro("Convert ProjID to RouteID", opts)

  // Open the route's stop dbd and add the scen_hwy
  master_stops_dbd = Substitute(master_rts_copy, ".rts", "S.dbd", )
  opts = null
  opts.file = master_stops_dbd
  {map, } = RunMacro("Create Map", opts)
  {slyr} = GetDBLayers(master_stops_dbd)
  {nlyr, llyr} = GetDBLayers(scen_hwy)
  AddLayer(map, nlyr, scen_hwy, nlyr)
  AddLayer(map, llyr, scen_hwy, llyr)

  // Create a selection set of route stops from the proj_list using
  // the route IDs. (The ProjID field is not in the stops dbd.)
  SetLayer(slyr)
  route_stops = "scenario routes"
  for i = 1 to v_rid.length do
    id = v_rid[i]

    id = if TypeOf(id) = "string" then "'" + id + "'" else String(id)
    qry = "Select * where Route_ID = " + id
    operation = if i = 1 then "several" else "more"
    SelectByQuery(route_stops, operation, qry)
  end

  /*
  Add stop layer fields. The tour table required to create a fresh route
  system requires the following fields:
  Master_Route_ID
  Node_ID
  Stop_Flag
  Stop_ID
  Stop_Name

  On a freshly-created route system, only the following fields are present
  on the stop layer:
  Route_ID (can be renamed to Master_Route_ID)
  STOP_ID (can be renamed to Stop_ID)

  Thus, the following fields must be created:
  Stop_Flag (filled with 1 because these are stop records)
  Node_ID (filled by tagging stops to nodes)
  Stop_Name (left empty)

  A final field "missing_node" is added for reporting purposes.
  */
  a_fields = {
    {"Stop_Flag", "Integer", 10,,,,,"Filled with 1s"},
    {"Stop_Name", "Character", 10,,,,,""},
    {"Node_ID", "Integer", 10,,,,,"Scenario network node id"},
    {"missing_node", "Integer", 10,,,,,
    "1: a stop in the master rts could not find a nearby node"}
  }
  RunMacro("Add Fields", {view: slyr, a_fields: a_fields, initial_values:{1, , , 0}})

  // Create a selection set of centroids on the node layer. These will be
  // excluded so that routes do not pass through them. Also create a
  // non-centroid set.
  SetLayer(nlyr)
  centroid_set = CreateSet("centroids")
  num_centroids = SelectByQuery(centroid_set, "several", centroid_qry)
  non_centroid_set = CreateSet("non-centroids")
  SetInvert(non_centroid_set, centroid_set)

  // If provided, use the link_qry to further reduce the non_centroid_set
  if link_qry <> null then do
    SetLayer(llyr)
    route_link_set = CreateSet("route links")
    n = SelectByQuery(route_link_set, "several", link_qry)
    if n = 0 then Throw("'link_qry' results in 0 valid links for routes to use.")
    SetLayer(nlyr)
    route_link_nodes = CreateSet("route link nodes")
    SelectByLinks(route_link_nodes, "several", "route links", )
    SetAND(non_centroid_set, {non_centroid_set, route_link_nodes})
  end

  // Perform a spatial join to match scenario nodes to master stops.
  opts = null
  opts.master_layer = slyr
  opts.master_set = route_stops
  opts.slave_layer = nlyr
  opts.slave_set = non_centroid_set
  jv = RunMacro("Spatial Join", opts)

  // Transfer the scenario node ID into the Node_ID field
  v = GetDataVector(jv + "|", nlyr + ".ID", )
  SetDataVector(jv + "|", slyr + ".Node_ID", v, )
  CloseView(jv)

  // The spatial join leaves "slave_id" and "slave_dist" fields.
  // Use them to determine missing nodes and then remove them.
  SetLayer(slyr)
  set = CreateSet("set")
  qry = "Select * where slave_dist <> null and slave_id = null"
  n = SelectByQuery(set, "several", qry)
  if n > 0 then do
    opts = null
    opts.Constant = 1
    v = Vector(n, "Long", opts)
    SetDataVector(slyr + "|" + set, "missing_node", v, )
    DeleteSet(set)
  end
  RunMacro("Remove Field", slyr, {"slave_id", "slave_dist"})

  // Read in the selected records to a data frame
  stop_df = CreateObject("df")
  opts = null
  opts.view = slyr
  opts.set = route_stops
  stop_df.read_view(opts)

  // shape_stop
  // Some stops on the master rts can be marked as shape stops, which
  // are used to improve the accuracy of the resulting route, but should
  // not be assigned as stops. Handle those here. Test to make sure the
  // shape_stop field exists so as not to make this field a requirement.
  if delete_shape_stops then do
    if stop_df.in("shape_stop", stop_df.colnames()) then do
      v_shape_stop = stop_df.get_col("shape_stop")
      v_stop_flag = stop_df.get_col("Stop_Flag")
      v_stop_flag = if (v_shape_stop = 1) then 0 else 1
      stop_df.mutate("Stop_Flag", v_stop_flag)
    end
  end

  // In order to draw routes to nodes in the right order, sort by
  // Route_ID and then mile post.
  stop_df.arrange({"Route_ID", "Milepost"})

  // Create a table with the proper format to be read by TC's
  // create-route-from-table method. In TC6 help, this is called
  // "Creating a Route System from a Tour Table", and is in the drop down
  // menu Route Systems -> Utilities -> Create from table...
  // Fields:
  // Master_Route_ID
  // Node_ID
  // Stop_Flag
  // Stop_ID
  // Stop_Name
  create_df = stop_df.copy()
  create_df.rename(
    {"Route_ID", "STOP_ID", "Stop Name"},
    {"Master_Route_ID", "Stop_ID", "Stop_Name"}
  )
  create_df.filter("missing_node <> 1")
  create_df.select(
    {"Master_Route_ID", "Node_ID", "Stop_Flag", "Stop_ID", "Stop_Name"}
  )
  tour_table = out_dir + "/create_rts_from_table.bin"
  create_df.write_bin(tour_table)

  // Create a simple network
  opts = null
  opts.llyr = llyr
  opts.centroid_qry = centroid_qry
  opts.link_qry = link_qry
  net_file = RunMacro("Create Simple Roadway Net", opts)

  // Get the name of the master (copy) route layer
  {, , a_info} = GetRouteSystemInfo(master_rts_copy)
  rlyr = a_info.Name

  // Call TransCAD macro for importing a route system from a stop table.
  Opts = null
  Opts.Input.Network = net_file
  Opts.Input.[Link Set] = {scen_hwy + "|" + llyr, llyr}
  Opts.Input.[Tour Table] = {tour_table}
  Opts.Global.[Cost Field] = 1
  Opts.Global.[Route ID Field] = 1
  Opts.Global.[Node ID Field] = 2
  Opts.Global.[Include Stop] = 1
  Opts.Global.[RS Layers].RouteLayer = rlyr
  Opts.Global.[RS Layers].StopLayer = slyr
  Opts.Global.[Stop Flag Field] = 3
  Opts.Global.[User ID Field] = 2
  Opts.Output.[Output Routes] = output_rts_file
  ret_value = RunMacro("TCB Run Operation", "Create RS From Table", Opts, &Ret)
  if !ret_value then Throw("Create RS From Table failed")
  // The tcb method leaves a layer open. Use close all to close it and the map.
  RunMacro("Close All")

  // The new route system is created without attributes, but with Time and
  // Distance fields added. Remove those fields and then join back the originals.
  vw_temp = OpenTable("vw_temp", "FFB", {Substitute(output_rts_file, ".rts", "R.bin", )})
  RunMacro("Remove Field", vw_temp, "Time")
  RunMacro("Remove Field", vw_temp, "Distance")
  CloseView(vw_temp)
  master_df = CreateObject("df")
  master_df.read_bin(
    Substitute(master_rts_copy, ".rts", "R.bin", )
  )
  scen_df = CreateObject("df")
  scen_df.read_bin(
    Substitute(output_rts_file, ".rts", "R.bin", )
  )

  scen_df.remove({"Route_Name", "Time", "Distance"})
  scen_df.left_join(master_df, "Master_Route_ID", "Route_ID")
  scen_df.desc = CopyArray(master_df.desc)
  scen_df.update_bin(
    Substitute(output_rts_file, ".rts", "R.bin", )
  )
  RunMacro("Close All")
  
  // Join any extra stop attributes (like dwell time)
  master_df = CreateObject("df")
  master_df.read_bin(
    Substitute(master_rts_copy, ".rts", "S.bin", )
  )
  scen_df = CreateObject("df")
  scen_df.read_bin(
    Substitute(output_rts_file, ".rts", "S.bin", )
  )
  master_df.remove({"Stop_Flag", "Stop_Name", "Node_ID", "missing_node"})
  scen_df.rename("[Stop_ID:1]", "stop_id_orig")  
  scen_df.left_join(master_df, "stop_id_orig", "Stop_ID")
  scen_df.desc = CopyArray(master_df.desc)
  scen_df.set_desc("stop_id_orig", "The stop ID in the master network")
  scen_df.update_bin(
    Substitute(output_rts_file, ".rts", "S.bin", )
  )

  // Reload the route system, which takes care of a few issues created by the
  // create-from-stops and join steps.
  opts = null
  opts.file = output_rts_file
  {map, a_layers} = RunMacro("Create Map", opts)
  ReloadRouteSystem(output_rts_file)

  // Clean up the files created by this macro that aren't needed anymore
  RunMacro("Close All")
  DeleteTableFiles("FFB", tour_table, )
  DeleteFile(net_file)
EndMacro

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
  master_rts_copy = out_dir + "/" + filename + ext
  opts = null
  opts.rts_file = master_rts_copy
  master_hwy_copy = RunMacro("Get RTS Roadway File", opts)

  // Get project IDs from the project list and convert to route ids on both
  // the master and scenario route systems.
  proj = OpenTable("projects", "CSV", {proj_list, })
  v_pid = GetDataVector(proj + "|", "ProjID", )
  if TypeOf(v_pid) = "null" then Throw("No transit project IDs found")
  if TypeOf(v_pid[1]) <> "string" then v_pid = String(v_pid)
  CloseView(proj)
  opts = null
  opts.rts_file = master_rts_copy
  opts.v_pid = v_pid
  {v_rid_m, v_rev_pid} = RunMacro("Convert ProjID to RouteID", opts)
  opts.rts_file = output_rts_file
  {v_rid_s, } = RunMacro("Convert ProjID to RouteID", opts)

  // Summarize the number of missing nodes by route. In order to have
  // all the fields in one table, you have to open the RTS file, which
  // links multiple tables together.
  opts = null
  opts.file = master_rts_copy
  {master_map, {rlyr_m, slyr_m, , , llyr_m}} = RunMacro("Create Map", opts)
  stops_df = CreateObject("df")
  opts = null
  opts.view = slyr_m
  opts.fields = {"Route_ID", "missing_node"}
  stops_df.read_view(opts)
  stops_df.mutate("missing_node", nz(stops_df.get_col("missing_node")))
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
    length_m = RunMacro("Get Route Length", opts)
    // Calculate the route length in the scenario rts
    opts = null
    opts.rlyr = rlyr_s
    opts.llyr = llyr_s
    opts.lookup_field = "Route_ID"
    opts.id = rid_s
    length_s = RunMacro("Get Route Length", opts)

    // calculate difference and percent difference
    diff = length_s - length_m
    pct_diff = round(diff / length_m * 100, 2)

    // store this information in a named array
    data.projid = data.projid + {pid}
    data.master_route_id = data.master_route_id + {rid_m}
    data.scenario_route_id = data.scenario_route_id + {rid_s}
    data.master_length = data.master_length + {length_m}
    data.scenario_length = data.scenario_length + {length_s}
    data.diff = data.diff + {diff}
    data.pct_diff = data.pct_diff + {pct_diff}
  end

  // Close both maps
  CloseMap(master_map)
  CloseMap(scen_map)

  // Convert the named array into a data frame
  length_df = CreateObject("df", data)

  // Create the final data frame by joining the missing stops and length DFs
  final_df = length_df.copy()
  final_df.left_join(stops_df, "master_route_id", "Route_ID")
  final_df.rename("missing_node", "missing_stops")
  final_df.write_csv(out_dir + "/_rts_creation_results.csv")


  // Clean up files
  RunMacro("Close All")
  DeleteRouteSystem(master_rts_copy)
  if GetFileInfo(Substitute(master_rts_copy, ".rts", "R.bin", )) <> null
    then DeleteFile(Substitute(master_rts_copy, ".rts", "R.bin", ))
  if GetFileInfo(Substitute(master_rts_copy, ".rts", "R.BX", )) <> null
    then DeleteFile(Substitute(master_rts_copy, ".rts", "R.BX", ))
  if GetFileInfo(Substitute(master_rts_copy, ".rts", "R.DCB", )) <> null
    then DeleteFile(Substitute(master_rts_copy, ".rts", "R.DCB", ))
  DeleteDatabase(master_hwy_copy)
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
Determines the length of the links that make up a route.
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
  Length of route
*/

Macro "Get Route Length" (MacroOpts)

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

  return(length)
EndMacro
