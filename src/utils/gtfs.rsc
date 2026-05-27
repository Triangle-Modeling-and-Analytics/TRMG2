/*
Creates a dbox accessed from the TRMG2 drop down menu.
Imports a GTFS file into a route system on a given link layer dbd.
*/

Macro "Open GTFS Dbox"
    RunDbox("GTFS")
endmacro

dBox "GTFS" location: x, y, 75, 10
    Title: "GTFS Import" toolbox NoKeyBoard

    close do
        return()
    enditem

    init do
        static x, y, link_dbd, gtfs_files, route_buffer
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

    Frame 2, 1.8, 65, 4 Prompt: "GTFS Files"

    // The GTFS file
    // Edit Text 11, 0, 50 Prompt: "GTFS File:" Variable: gtfs_file
    Button 3, 3, 15, 1 Prompt: "Add GTFS File" do
        on error, escape goto skip1
        gtfs_file = ChooseFile(
            {{"TXT (*.txt)", "routes.txt"}}, 
            "Choose GTFS Route File", 
            {"Initial Directory": Args.[Base Folder]}
        )
        gtfs_files = gtfs_files + {gtfs_file}
        gtfs_idx = gtfs_files.length
        skip1:
        on error default
    enditem

    // List GTFS files and allow removal
    Popdown Menu "GTFS Files" same, after, 35, 4 list: gtfs_files variable: gtfs_idx
    Button after, same, 15, 1 Prompt: "Remove Selected" do
        if gtfs_idx = null then return()
        gtfs_files = ExcludeArrayElements(gtfs_files, gtfs_idx, 1)
    enditem
    Button after, same Prompt: "Clear All" do
        gtfs_files = null
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
    Button 3, 8, 10 Prompt: "Run" do
        if link_dbd = null then do
            ShowMessage("Choose a Link DBD file.")
        end else if gtfs_files = null then do
            ShowMessage("Choose a GTFS file.")
        end else do
            Args.gtfs_files = gtfs_files
            Args.link_dbd = link_dbd
            Args.route_buffer = route_buffer
            RunMacro("Import GTFS Wrapper", Args)
            ShowMessage("Done!")
        end
    enditem
    Button after, same, 10 Prompt: "Quit" do
        Return()
    enditem
enddBox

/*
The user can select multiple GTFS files. This will loop over each
one and then merge the resulting route systems together at the end.
*/

Macro "Import GTFS Wrapper" (Args)
    
    gtfs_files = Args.gtfs_files
    link_dbd = Args.link_dbd

    {drive, folder, , } = SplitPath(link_dbd)
    out_dir = drive + folder
    final_rts = out_dir + "routes.rts"
    Args.temp_dir = out_dir + "temp_rts"
    if GetDirectoryInfo(Args.temp_dir, "All") = null then CreateDirectory(Args.temp_dir)

    for i = 1 to gtfs_files.length do
        gtfs_file = gtfs_files[i]
        if i = 1 
            then out_rts_file = final_rts
            else out_rts_file = Args.temp_dir + "\\routes_" + String(i) + ".rts"

        Args.output_rts_file = out_rts_file
        Args.gtfs_file = gtfs_file
        RunMacro("Import GTFS", Args)

        if i > 1 then do
            Args.rts_to_merge = out_rts_file
            Args.output_rts_file = final_rts
            RunMacro("Merge Route Systems2", Args)
        end
    end
Endmacro

/*
This macro is called by the GTFS dbox after the user clicks "Run". 
It takes the GTFS file and link layer DBD as arguments and runs the code 
to import the GTFS data onto the link layer.
*/

Macro "Import GTFS" (Args)

    gtfs_file = Args.gtfs_file
    link_dbd = Args.link_dbd
    output_rts_file = Args.output_rts_file
    route_buffer = Args.route_buffer

    net_file = RunMacro("Create Simple Roadway Net", {
        hwy_dbd: link_dbd,
        link_qry: "Select * where HCMType <> null and HCMType <> 'CC'"
    })

    {drive, folder, , } = SplitPath(gtfs_file)
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