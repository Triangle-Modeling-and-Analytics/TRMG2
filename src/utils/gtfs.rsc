/*
Creates a dbox accessed from the TRMG2 drop down menu.
Imports a GTFS file into a route system on a given link layer dbd.
*/

Macro "Open GTFS Dbox"
    RunDbox("GTFS")
endmacro

dBox "GTFS" location: x, y, 82, 25
    Title: "GTFS Import" toolbox NoKeyBoard

    close do
        return()
    enditem

    init do
        static x, y
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

    Button 30, after Prompt: "Quit" do
        Return()
    enditem
enddBox