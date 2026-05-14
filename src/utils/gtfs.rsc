/*
Creates a dbox accessed from the TRMG2 drop down menu.
Imports a GTFS file into a route system on a given link layer dbd.
*/

Macro "Open GTFS Dbox"
    RunDbox("GTFS")
endmacro

dBox "GTFS" location: x, y, 75, 8
    Title: "GTFS Import" toolbox NoKeyBoard

    close do
        return()
    enditem

    init do
        static x, y, link_dbd, gtfs_file
        if x = null then x = -3
        mr = CreateObject("Model.Runtime")
        Args = mr.GetValues()
    enditem

    // The GTFS file
    Edit Text 11, 0, 50 Prompt: "GTFS File:" Variable: gtfs_file
    Button after, same, 5, 1 Prompt: "..." do
        on error, escape goto skip1
        gtfs_file = ChooseFile(
            {{"TXT (*.txt)", "routes.txt"}}, 
            "Choose GTFS Route File", 
            {"Initial Directory": Args.[Base Folder]}
        )
        skip1:
        on error default
    enditem

    // The link layer DBD
    Edit Text 11, after, 50 Prompt: "Link Layer DBD:" Variable: link_dbd
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
    
    // Run/Quit buttons
    Button 22, after Prompt: "Run" do
        if gtfs_file = null then do
            ShowMessage("Choose a GTFS file.")
        end else if link_dbd = null then do
            ShowMessage("Choose a Link DBD file.")
        end else do
            Args.gtfs_file = gtfs_file
            Args.link_dbd = link_dbd
            RunMacro("Import GTFS", Args)
            ShowMessage("Done!")
        end
    enditem
    Button after, same Prompt: "Quit" do
        Return()
    enditem
enddBox

/*
This macro is called by the GTFS dbox after the user clicks "Run". 
It takes the GTFS file and link layer DBD as arguments and runs the code 
to import the GTFS data onto the link layer.
*/

Macro "Import GTFS" (Args)

    gtfs_file = Args.gtfs_file
    link_dbd = Args.link_dbd

    net_file = RunMacro("Create Simple Roadway Net", {
        hwy_dbd: link_dbd,
        link_qry: "Select * where HCMType <> null and HCMType <> 'CC'"
    })

    {drive, folder, , } = SplitPath(gtfs_file)
    gtfs_dir = drive + folder
    {drive, folder, , } = SplitPath(link_dbd)
    out_dir = drive + folder
    output_rts_file = out_dir + "routes.rts"

    gtfs = CreateObject("GTFSImporter", {
        RoadDatabase: link_dbd,
        GTFSFolder: gtfs_dir,
        RouteFile: output_rts_file,
        NetworkFile: net_file,
        RouteBuffer: 50/5280
    })
    gtfs.ServicesFlag = 0
    gtfs.Import({DropPhysicalStops: true})
Endmacro