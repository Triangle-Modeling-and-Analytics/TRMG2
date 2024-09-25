/*
This contains the dialog box and control macros for the CoC analysis.
Note that these macros call into existing macros in the summaries file that
run when the model runs, but with custom arguments that modify their behavior.
*/

Macro "Open CoC Dbox" (Args)
    RunDbox("CoC", Args)
endmacro

dBox "CoC" (Args) location: x, y, 82, 25
    Title: "Communities of Concern Analysis" toolbox NoKeyBoard

    close do
        return()
    enditem

    init do
        static x, y, andor_index, andor
        if x = null then x = -3
        if andor_index = null then andor_index = 2
        if andor = null then andor = "or"
        mpo_index = {1, 2}
        mpo_options = {"CAMPO", "DCHC"}
        how_index = 1
        how = "selection"
        moreless_list = {"or more", "exactly", "or less"}
        moreless_index = 1
        moreless = "or more"

        mr = CreateObject("Model.Runtime")
        Args = mr.GetValues()
        coc_csv = Args.[Base Folder] + "/other/communities_of_concern/Communities of Concern.csv"
        if GetFileInfo(coc_csv) <> null then do
            coc_defs = RunMacro("get_coc_defs", coc_csv)
            v = Vector(coc_defs.coc_categories.length + 1, "integer", {{"Sequence", 0, 1}})
            spinner_list = V2A(v)
            cat_list = coc_defs.coc_categories
        end
    enditem

    // The CoC definition file
    Edit Text 11, 0, 50 Prompt: "CoC Definition File:" Variable: coc_csv
    Button after, same, 5, 1 Prompt: "..." do
        on error, escape goto skip2
        coc_csv = ChooseFile(
            {{"CSV (*.csv)", "*.csv"}}, 
            "Choose CoC Definition File", 
            {"Initial Directory": Args.[Base Folder] + "/other/communities_of_concern"}
        )
        skip2:
        on error default
        if GetFileInfo(coc_csv) <> null then do
            coc_defs = RunMacro("get_coc_defs", coc_csv)
            v = Vector(coc_defs.coc_categories.length, "integer", {{"Sequence", 1, 1}})
            spinner_list = V2A(v)
            cat_list = coc_defs.coc_categories
        end
    enditem

    // Choose whether to select categories or a count of categories.
    Radio List 8, 2, 60, 2 Prompt: "Select zones using:" Variable: how_index
    Radio Button "Selection" 10, 3 Prompt: "Selected Categories" do
        DisableItem("spinner")
        DisableItem("moreless")
        EnableItem("coc_list")
        EnableItem("coc_radio")
        cat_list = coc_defs.coc_categories
        coc_cat_index = coc_cat_index_backup
        how = "selection"
    enditem
    Radio Button "Number" 43, 3 Prompt: "Number of Categories" do
        DisableItem("coc_list")
        DisableItem("coc_radio")
        coc_cat_index_backup = coc_cat_index
        coc_cat_index = null
        cat_list = null
        EnableItem("spinner")
        EnableItem("moreless")
        how = "number"
    enditem

    // Scroll list and radio buttons for CoC categories
    Scroll List "coc_list" 11, 5, 15, 10 Prompt: "CoC Categories" List: cat_list Multiple Variables: coc_cat_index do
        for index in coc_cat_index do
            coc_categories = coc_categories + {cat_list[index]}
        end
    enditem
    Radio List "coc_radio" same, 16, 15, 4 Prompt: "Combine categories using:" Variable: andor_index
    Radio Button "and" 13, 17.25 Prompt: "and" do
        andor = "and"
    enditem
    Radio Button "or" same, 18.75 Prompt: "or" do
        andor = "or"
    enditem

    // Spinner for the number of categories and popdown for more/exactly/less
    Spinner "spinner" 56, 5, 7, 1 Disabled Prompt: "Number of Categories" List: spinner_list Variable: num_cats
    Popdown Menu "moreless" same, after, 10 Disabled List: moreless_list Variable: moreless_index do
        moreless = moreless_list[moreless_index]
    enditem

    // Scroll list for MPOs
    Scroll List 50, 16, 15, 4 Prompt: "MPO Filter" List: coc_defs.mpo_options Multiple Variables: mpo_index do
        mpo_options = null
        for index in mpo_index do
            mpo_options = mpo_options + {coc_defs.mpo_options[index]}
        end
    enditem

    // Run/Quit/Help buttons
    Button 22, 22 Prompt: "Run" do
        if coc_csv = null then do
            ShowMessage("Choose a CoC definition file.")
        end else if
            how = "selection" and coc_cat_index = null then do
            ShowMessage("Choose at least one CoC category.")
        end else if
            how = "number" and num_cats = null then do
            ShowMessage("Choose a number of categories.")
        end else do
            Args.how = how
            Args.coc_categories = coc_categories
            Args.all_coc_categories = coc_defs.coc_categories
            Args.andor = andor
            Args.num_cats = S2I(num_cats)
            Args.moreless = moreless            
            Args.mpo_options = mpo_options
            Args.coc_csv = coc_csv
            RunMacro("CoC", Args)
            ShowMessage("Done!")
        end
    enditem
    Button 30, same Prompt: "Quit" do
        Return()
    enditem
    Button 38, same Prompt: "Help" do
        ShowMessage(
        "This tool lets you pick and choose which CoC definitions to " +
        "use before running the CoC analysis. The results will be saved " +
        "in the scenario folder under 'output/_summaries/coc."
        )
    enditem

enddbox

/*
Dbox helper macro. Reads the coc csv and returns information like the 
categories, MPOs, and counties.
*/

Macro "get_coc_defs" (coc_csv)

    def_tbl = CreateObject("Table", coc_csv)
    field_names = def_tbl.GetFieldNames()
    to_skip = {"TAZ", "MPO", "COUNTY"}
    for field_name in field_names do
        if to_skip.position(field_name) > 0 then continue
        coc_categories = coc_categories + {field_name}
    end
    mpo_options = def_tbl.MPO
    mpo_options = V2A(SortVector(mpo_options, {Unique: true}))
    county_options = def_tbl.COUNTY
    county_options = V2A(SortVector(county_options, {Unique: true}))

    coc_defs.coc_categories = coc_categories
    coc_defs.mpo_options = mpo_options
    coc_defs.county_options = county_options
    return(coc_defs)
endmacro

/*

*/

Macro "CoC" (Args)
    
    se_file = Args.SE
    coc_csv = Args.coc_csv
    how = Args.how
    coc_categories = Args.coc_categories
    all_coc_categories = Args.all_coc_categories
    andor = Args.andor
    num_cats = Args.num_cats
    moreless = Args.moreless
    mpo_options = Args.mpo_options

    coc_def = CreateObject("Table", coc_csv)
    se_tbl = CreateObject("Table", se_file)
    se_tbl.AddField({
        FieldName: "CoC_dc", 
        Type: "integer", 
        Description: "Community of Concern dummy variable"
    })
    joined = se_tbl.Join({
        Table: coc_def,
        LeftFields: "TAZ",
        RightFields: "TAZ"
    })
    fields = all_coc_categories + {"MPO"}
    data = joined.GetDataVectors({FieldNames: fields, NamedArray: true})

    // If the user picked categories from the list
    if how = "selection" then do
        // Read the CoC definitions and combine them appropriately
        for cat in coc_categories do
            v_cat = data.(cat)
            if cat = coc_categories[1] then do
                v_combined_cat = v_cat
                folder_name = cat
            end else do
                if andor = "and" then do
                    v_combined_cat = v_combined_cat * v_cat
                    folder_name = folder_name + " and " + cat
                end else do
                    v_combined_cat = v_combined_cat + v_cat
                    folder_name = folder_name + " or " + cat
                end
            end
        end
        v_combined_cat = if v_combined_cat > 0 then 1 else 0
    end

    // If the user picked a number of categories
    if how = "number" then do
        for cat in all_coc_categories do
            if cat = all_coc_categories[1] then do
                v_combined_cat = data.(cat)
            end else do
                v_combined_cat = v_combined_cat + data.(cat)
            end
        end
        v_combined_cat = if moreless = "or more" then v_combined_cat >= num_cats else
                        if moreless = "exactly" then v_combined_cat = num_cats else
                        if moreless = "or less" then v_combined_cat <= num_cats
        folder_name = String(num_cats) + " " + moreless + " categories"
    end

    // Next consider MPOs. Logic always assumes 'or' for multiple MPO selections
    v_combined_mpo = Vector(v_combined_cat.length, "integer", {Constant: 0})
    folder_name = folder_name + " mpo "
    for mpo in mpo_options do
        v_combined_mpo = if data.MPO = mpo then 1 else v_combined_mpo
        folder_name = folder_name + Left(mpo, 1)
    end
    v_combined_cat = v_combined_cat * v_combined_mpo
    

    // Check that at least one TAZ is marked as a CoC
    if v_combined_cat.sum() = 0 then do
        ShowMessage(
            "No TAZs were marked as a Community of Concern.\n" +
            "Consider using 'or' instead of 'and'.\n" + 
            "Also check your MPO filter."
        )
        return()
    end

    // set the CoC field in the SE file
    se_tbl.CoC_dc = v_combined_cat
    joined = null
    se_tbl = null
    coc_def = null

    Args.weight_fields = {"CoC"}
    Args.names = {"CoC"}
    Args.summary_dir = Args.[Scenario Folder] + "/output/_summaries/coc/" + folder_name
    if GetDirectoryInfo(Args.summary_dir, "All") = null then CreateDirectory(Args.summary_dir)
    pbar = CreateObject("G30 Progress Bar", "Summarizing CoCs", false, )
    RunMacro("Disadvantage Community Skims", Args)
    RunMacro("Disadvantage Community Mode Shares", Args)
    RunMacro("Disadvantage Community Mapping", Args)
    RunMacro("Summarize NM Disadvantage Community", Args)
    pbar.Destroy()
endmacro