Macro "Open Delete Files Tool Dbox" (Args)
	RunDbox("Delete Files Tool", Args)
endmacro

dBox "Delete Files Tool" (Args) center, center, 40, 6 Title: "Delete Files Tool" Help: "test" toolbox

    close do
        return()
    enditem

    init do
        static action_list, action_index

        action_list = {"Only probability and logsum matrices", "Everything except assignment"}

        EnableItem("Select Files to be Deleted")
    enditem

    // Select files to be deleted
    Popdown Menu "Select Files to be Deleted" 25,1,10,5 Prompt: "Select Files to be Deleted" 
        List: action_list Variable: action_index 
    
    Button 6, 4 Prompt: "Delete Files" do
        RunMacro("Delete Folder and Files", Args, action_index)
        ShowMessage("A slim verison of output folder has been created.")
	return(1)
    enditem

    Button 20, same Prompt: "Quit" do
        Return()
    enditem

    Button 28, same Prompt: "Help" do
        ShowMessage(
        "This tool is used to create a slim version of output folder by deleting unnecessary files. You" +
         "can choose to either deleting probability and logsum matrices only or everything except assignment folder." +
         "Doing such helps reduce scenario folder size by 40-80 GB. Note that after running this tool, other utility" +
         "tools may no longer work. Please run desired utility tools first and then delete unnecessary files.\n\n"
     )
    enditem
enddbox

Macro "Delete Folder and Files" (Args, action_index)
    scen_dir = Args.[Scenario Folder]
    dir_deletelist = null
    
    if action_index = 1 then do
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
        
        dir_deletelist = {resident_mode_logsum_dir, resident_mode_prob_dir, 
                    resident_dc_logsum_dir, resident_dc_prob_dir, 
                    univ_mode_logsum_dir, univ_mode_prob_dir,
                    nhb_dc_prob_dir}
    end
    else do
        arr_dirs = GetDirectoryInfo(scen_dir + "\\output\\*.*", "Folder")
        for arr_dir in arr_dirs do
            dirname = arr_dir[1]
            if dirname <> "networks" and dirname <> "assignment" then dir_deletelist = dir_deletelist + {scen_dir + "\\output\\" + dirname}
        end

    end

    // Delete files
    for dir_delete in dir_deletelist do
        
        RunMacro("Delete Files", dir_delete)

        sub_folders = GetDirectoryInfo(dir_delete + "\\*.*", "Folder")
        if sub_folders <> null then do
            for sub_folder in sub_folders do
                sub_folder_path = dir_delete + "\\" + sub_folder[1] + "\\"
                dir = CreateObject("CC.Directory", sub_folder_path)
                dir.Delete()
            end
        end
        if GetDirectoryInfo(dir_delete, "All") <> null then RemoveDirectory(dir_delete)
    end

endmacro


Macro "Delete Files" (dir)
    files = GetDirectoryInfo(dir + "/*", "File")
        
    for i = 1 to files.length do
        file = files[i][1]
        filepath = dir + "/" + file
        DeleteFile(filepath)
    end
    if GetDirectoryInfo(dir + "\\*.*", "Folder") = null then RemoveDirectory(dir)
endmacro