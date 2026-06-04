/*
Creates a dbox accessed from the TRMG2 drop down menu.
Imports a route file into a route system on a given link layer dbd.
*/

Macro "Open Route Dbox"
    RunDbox("Route")
endmacro

dBox "Route" location: x, y, 75, 11
    Title: "Route Import" toolbox NoKeyBoard

    close do
        return()
    enditem

    init do
        static x, y, link_dbd, route_files, ext, route_buffer
        if x = null then x = -3
        if route_buffer = null then route_buffer = 10
        mr = CreateObject("Model.Runtime")
        Args = mr.GetValues()
    enditem

    // The link layer DBD
    Edit Text 15, 0, 50 Prompt: "Link Layer DBD:" Variable: link_dbd
    Button after, same, 5, 1 Prompt: "..." do
        on error, escape goto skip2
        link_dbd = ChooseFile(
            {{"DBD (*.dbd)", "*.dbd"}}, 
            "Choose Link DBD", 
            {"Initial Directory": Args.[Base Folder]}
        )
        skip2:
        on error default
    enditem

    Text 67, 1.5 Prompt: "(routes.rts will be created in the same folder as the link layer.)"

    Frame 2, 2.8, 65, 4 Prompt: "Route Files (either GTFS or RTS)"

    // Route file (either GTFS or RTS)
    Button 3, 4, 15, 1 Prompt: "Add Route File" do
        on error, escape goto skip1
        route_file = ChooseFile(
            {{"TXT (*.txt)", "routes.txt"}, {"RTS (*.rts)", "*.rts"}}, 
            "Choose Route File", 
            {"Initial Directory": Args.[Base Folder]}
        )
        {drive, path, file, ext} = SplitPath(route_file)
        // If the user selects a GTFS txt file, then we want to allow them to select multiple files.
        // If they select an RTS file, then we will just import that one file and ignore any others.
        if ext = ".txt" then do
            if route_files <> null then do
                for file in route_files do
                    {, , , ext_check} = SplitPath(file)
                    if ext_check = ".rts" then do
                        route_files = null
                        break
                    end
                end
            end
            route_files = route_files + {route_file}
            route_idx = route_files.length
        end else do
            route_files = {route_file}
            route_idx = 1
        end
        skip1:
        on error default
    enditem

    // List Route files and allow removal
    Popdown Menu "Route Files" same, after, 35, 4 list: route_files variable: route_idx
    Button after, same, 15, 1 Prompt: "Remove Selected" do
        if route_idx <> null 
            then route_files = ExcludeArrayElements(route_files, route_idx, 1)
    enditem
    Button after, same Prompt: "Clear All" do
        route_files = null
    enditem
    
    // Import buffer distance
    Edit Int 18, after, 10 Prompt: "Route Buffer (ft):" Variable: route_buffer
    Button after, same, 4, 1 Prompt: "?" do
        ShowMessage(
            "The route buffer is the distance that GTFS routes will be buffered " +
            "when being imported. An attempt will be made to only use links inside " +
            " this buffer. If a path can't be found, then all links will be used."
        )
    enditem

    // Run/Quit buttons
    Button 3, 9, 10 Prompt: "Run" do
        if link_dbd = null then do
            ShowMessage("Choose a Link DBD file.")
        end else if route_files = null then do
            ShowMessage("Choose a Route file.")
        end else do
            Args.route_files = route_files
            Args.link_dbd = link_dbd
            Args.route_buffer = route_buffer
            if ext = ".txt" 
                then RunMacro("Import GTFS Wrapper", Args)
                else RunMacro("Import RTS", Args)
            ShowMessage("Done!")
        end
    enditem
    Button after, same, 10 Prompt: "Quit" do
        Return()
    enditem
enddBox

/*
The user can select multiple Route files. This will loop over each
one and then merge the resulting route systems together at the end.
*/

Macro "Import GTFS Wrapper" (Args)
    route_files = Args.route_files
    link_dbd = Args.link_dbd

    {drive, folder, , } = SplitPath(link_dbd)
    out_dir = drive + folder
    final_rts = out_dir + "routes.rts"
    Args.temp_dir = out_dir + "temp_rts"
    if GetDirectoryInfo(Args.temp_dir, "All") = null then CreateDirectory(Args.temp_dir)

    for i = 1 to route_files.length do
        route_file = route_files[i]
        if i = 1 
            then out_rts_file = final_rts
            else out_rts_file = Args.temp_dir + "\\routes_" + String(i) + ".rts"

        Args.output_rts_file = out_rts_file
        Args.route_file = route_file
        RunMacro("Import GTFS", Args)

        if i > 1 then do
            Args.rts_to_merge = out_rts_file
            Args.output_rts_file = final_rts
            RunMacro("Merge Route Systems2", Args)
        end
    end
Endmacro

/*
This macro is called by the Route dbox after the user clicks "Run". 
It takes the Route file and link layer DBD as arguments and runs the code 
to import the Route data onto the link layer.
*/

Macro "Import GTFS" (Args)

    route_file = Args.route_file
    link_dbd = Args.link_dbd
    output_rts_file = Args.output_rts_file
    route_buffer = Args.route_buffer

    net_file = RunMacro("Create Simple Roadway Net", {
        hwy_dbd: link_dbd,
        link_qry: "Select * where HCMType <> 'CC'"
    })

    {drive, folder, , } = SplitPath(route_file)
    gtfs_dir = drive + folder

    gtfs = CreateObject("GTFSImporter", {
        RoadDatabase: link_dbd,
        GTFSFolder: gtfs_dir,
        RouteFile: output_rts_file,
        NetworkFile: net_file,
        RouteBuffer: route_buffer / 5280 // convert feet to miles
    })
    gtfs.ServicesFlag = 0
    gtfs.Import({DropPhysicalStops: true})
Endmacro

/*
Used to merge route systems if the user provides multiple GTFS files.
*/

Macro "Merge Route Systems2" (MacroOpts)
  output_rts_file = MacroOpts.output_rts_file
  rts_to_merge = MacroOpts.rts_to_merge

  rts = CreateObject("Map", output_rts_file)
  {nlyr, llyr, rlyr, slyr} = rts.GetLayerNames()
  rts2 = CreateObject("Map", rts_to_merge)
  {nlyr2, llyr2, rlyr2, slyr2} = rts2.GetLayerNames()

  // Create route and stop field arrays to merge attributes
  tbl = CreateObject("Table", rlyr2)
  field_names = tbl.GetFieldNames()
  dont_include = {"Route_ID", "Length"}
  for field_name in field_names do
    if dont_include.position(field_name) > 0 then continue
    route_fields = route_fields + {{field_name, field_name}}
  end
  stop_fields = {{"shape_stop", "shape_stop"}, {"Node_ID", "Node_ID"}}

  opts = null
  opts.[Route Fields] = route_fields
  opts.[Stop Fields] = stop_fields
  MergeRouteSystems(rlyr, rlyr2 + "|", opts)

  tbl = CreateObject("Table", rlyr)
  tbl.DropFields("sel_temp")
  tbl = null
  rts = null
  rts2 = null

  // Delete the merged rts
  DeleteRouteSystem(rts_to_merge)
endmacro

/*
This macro leverages the same logic from the model's scenario creation step.
It just creates a temporary project list of all the transit routes and uses
that.
*/

Macro "Import RTS" (Args)
    
    route_files = Args.route_files
    route_file = route_files[1]
    link_dbd = Args.link_dbd
    output_rts_file = Args.output_rts_file
    route_buffer = Args.route_buffer

    // Create project list of all transit routes
    map = CreateObject("Map", route_file)
    {, , rlyr} = map.GetLayerNames()
    rtbl = CreateObject("Table", rlyr)
    field_names = rtbl.GetFieldNames()
    // Make sure ProjID exists since the project manager requires it. 
    // If it doesn't exist, then create it and populate with unique values.
    // Track if we added it so we know to delete it later.
    if field_names.position("ProjID") = 0 then do
        rtbl.AddField({FieldName: "ProjID", Type: "String"})
        num_records = rtbl.GetRecordCount()
        v = Vector(num_records, "Long", {{"Sequence", 1, 1}})
        v = String(v)
        rtbl.ProjID = v
        added_projid = "true"
    end
    v_pid = rtbl.ProjID
    pid_tbl = CreateObject("Table", {Fields: {{FieldName: "ProjID", Type: "String"}}})
    pid_tbl.AddRows(v_pid.length)
    pid_tbl.ProjID = v_pid
    {drive, path, file, ext} = SplitPath(link_dbd)
    project_file = drive + path + "temp_proj_list.csv"
    pid_tbl.Export({FileName: project_file})
    map = null
    rtbl = null
Throw()
    // Create scenario RTS using project manager
    scen_dir = Args.[Scenario Folder]
    opts = null
    opts.master_rts = Args.[Master Routes]
    opts.scen_hwy = Args.[Input Links]
    opts.proj_list = scen_dir + "/TransitProjectList.csv"
    opts.centroid_qry = "Centroid = 1"
    opts.link_qry = "HCMType <> null and HCMType <> 'CC'"
    {, , rts_name, ext} = SplitPath(scen_rts)
    opts.output_rts_file = rts_name + ext
    RunMacro("Transit Project Management", opts)

    // If we added ProjID field to the route file, then remove it
    if added_projid then do
        map = CreateObject("Map", route_file)
        {, , rlyr} = map.GetLayerNames()
        rtbl = CreateObject("Table", rlyr)
        rtbl.DropField("ProjID")
        rtbl = null
        map = null
    end
    
    DeleteFile(project_file)
EndMacro