Macro "Open Delete Files Tool Dbox" (Args)
	RunDbox("Delete Files Tool", Args)
endmacro

dBox "Delete Files Tool" (Args) center, center, 40, 8 Title: "Delete Files Tool" Help: "test" toolbox

    close do
        return()
    enditem

    Button 6, 4 Prompt: "Delete Files" do
        RunMacro("Delete Files", Args)
        ShowMessage("A slim verison of output folder has been created.")
	return(1)
    enditem
    Button 20, same Prompt: "Quit" do
        Return()
    enditem
    Button 28, same Prompt: "Help" do
        ShowMessage(
        "This tool is used to create a slim version of output folder by deleting unnecessary files (" +
         "i.e. probability matrics, logsums). Doing such helps reduce scenario folder size by ~40 GB. " +
         "Note that after running this tool, other utility tools may no longer work. Please run desired " +
         "utility tools first and then delete unnecessary files.\n\n"
     )
    enditem
enddbox

Macro "Delete Files" (Args)
    scen_dir = Args.[Scenario Folder]
    
    //set path
    resident_mode_dir = scen_dir + "\\output\\resident\\mode"
    resident_mode_logsum_dir = resident_mode_dir + "\\logsums"
    resident_mode_prob_dir = resident_mode_dir + "\\probabilities"

    resident_dc_dir = scen_dir + "\\output\\resident\\dc"
    resident_dc_logsum_dir = resident_dc_dir + "\\logsums"
    resident_dc_prob_dir = resident_dc_dir + "\\probabilities"

    univ_mode_dir = scen_dir + "\\output\\university\\mode"
    univ_mode_logsum_dir = univ_mode_dir + "\\logsums"
    univ_mode_prob_dir = univ_mode_dir + "\\probabilities"

    nhb_dc_prob_dir = scen_dir + "\\output\\resident\\nhb\\dc\\probabilities"
    
    dir_list = {resident_mode_logsum_dir, resident_mode_prob_dir, 
                resident_dc_logsum_dir, resident_dc_prob_dir, 
                univ_mode_logsum_dir, univ_mode_prob_dir,
                nhb_dc_prob_dir}

    // Delete files
    for dir in dir_list do

        //Create output matrix
        files = GetDirectoryInfo(dir + "/*", "File")
        
        for i = 1 to files.length do
            file = files[i][1]
            filepath = dir + "/" + file
            DeleteFile(filepath)
        end
        if GetDirectoryInfo(dir, "All") <> null then RemoveDirectory(dir)
    end

endmacro