Macro "Open Concatenate Files Dbox" (Args)
	RunDbox("Concatenate Files", Args)
endmacro

dBox "Concatenate Files" (Args) center, center, 60, 6 
    Title: "Concatenate Files" Help: "test" toolbox NoKeyBoard

    close do
        return()
    enditem

    init do
        static  Scenroot_Dir, Scen_Dir, Scen_Name
    
        Scenroot_Dir = Args.[Scenarios Folder]
        Scen_Dir = Args.[Scenario Folder]
        Scen_Name = Substitute(Scen_Dir, Scenroot_Dir + "\\", "",)

    enditem

    // Path
    Text 38, 1, 15 Prompt: "Run Scenario (selected in scenario list):" Variable: Scen_Name
    Text 20, 2, 50 Prompt: "Results will be saved in " Variable: Scen_Dir + "\\output\\_summaries"

    // Quit Button
    button 5, 4, 10 Prompt:"Quit" do
        Return(1)
    enditem

    // Run Button
    button 18, 4, 20 Prompt:"Generate Results" do 
        opts.model_dir = Args.[Base Folder]
        opts.scen_dir = Args.[Scenario Folder]
        opts.inputtable_file = opts.model_dir + "\\other\\_reportingtool\\Concatenate_tablenames.csv"
        opts.output_file = opts.scen_dir + "\\output\\_summaries\\concatenate_summary.csv"
        if !RunMacro("Concatenate Files", opts) then Throw("Something went wrong")
 
        ShowMessage("Reports have been created successfully.")
	return(1)
	
    exit:	
        showmessage("Something is wrong")	
        return(0)
    Enditem

    Button 41, 4, 10 Prompt: "Help" do
        ShowMessage(
        "This tool is used to export a model run’s csv files to one combined csv file."
     )
    enditem
enddbox


Macro "Concatenate Files" (Args)
    scen_dir = Args.scen_dir
    summary_dir = scen_dir + "\\output\\_summaries"
    inputtable_file = Args.inputtable_file
    output_file = Args.output_file
    if GetFileInfo(output_file) <> null then deleteFile(output_file)
    
    input_vw = OpenTable("inputtable", "CSV", {inputtable_file})  
    rh = GetFirstRecord(input_vw + "|", )
    while rh <> null do
        dir = input_vw.dir
        tablename = input_vw.tablename  
        if dir = null then goto skip
        csv_file = summary_dir + "\\" + dir + "\\" + tablename
        if GetFileInfo(csv_file) = null then do
            ShowMessage(tablename + " does not exist.")
            goto skip
        end

        outf = OpenFile(output_file, "a")
        inf = OpenFile(csv_file, "r")
        WriteLine(outf, tablename)       
        while not FileAtEOF(inf) do
            line = ReadLine(inf)
            WriteLine(outf, line)
        end
        WriteLine(outf, "\n")

        CloseFile(inf)
        CloseFile(outf)

        skip:
        rh = GetNextRecord(input_vw + "|", rh, )
    end
    CloseView(input_vw)
    
    return(1)
endmacro