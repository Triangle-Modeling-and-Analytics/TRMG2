/*
Dialog box for the merge tool and the macro used to open it from
the TRMG2 drop down menu.
*/

Macro "Open Merge Dbox" (Args)
	RunDbox("Merge", Args)
endmacro
dBox "Merge" (Args) location: x, y, , 15
    Title: "Master Layer Merge Tool" toolbox NoKeyBoard

    close do
        return()
    enditem

    init do
        static x, y, initial_dir, poly_dir, old_dbd, new_dbd, poly_dbd
        if x = null then x = -3
    enditem

    // Original Layer
    text 1, 0 variable: "Original Layer"
    text same, after, 40 variable: old_dbd framed
    button after, same, 6 Prompt: "..."  default do
        on escape goto nodir
        old_dbd = ChooseFile(
            {{"Original Link Layer", "*.dbd"}},
            "Select original link layer",
            {"Initial Directory": initial_dir}
        )
        {drive, path, name, ext} = SplitPath(old_dbd)
        initial_dir = drive + path
        nodir:
        on error, notfound, escape default
    enditem
    button after, same, 3 Prompt: "?"  do
        ShowMessage("The master link layer to be updated.")
    enditem

    // New Layer
    text 1, after variable: "New Layer"
    text same, after, 40 variable: new_dbd framed
    button after, same, 6 Prompt: "..."  do
        on escape goto nodir
        new_dbd = ChooseFile(
            {{"New Link Layer", "*.dbd"}},
            "Select new link layer",
            {"Initial Directory": initial_dir}
        )
        {drive, path, name, ext} = SplitPath(new_dbd)
        initial_dir = drive + path
        nodir:
        on error, notfound, escape default
    enditem
    button after, same, 3 Prompt: "?"  do
        ShowMessage("The new master link layer where some links are updated.")
    enditem

    // Polygon Layer
    text 1, after variable: "Polygon Layer"
    text same, after, 40 variable: poly_dbd framed
    button after, same, 6 Prompt: "..."  do
        on escape goto nodir
        poly_dir = Args.[Model Folder] + "\\other\\mpo_regions"
        poly_dbd = ChooseFile(
            {{"Polygon Layer", "*.dbd;*.cdf"}},
            "Select polygon layer",
            {{"Initial Directory", poly_dir}}
        )
        {drive, path, , } = SplitPath(poly_dbd)
        poly_dir = drive + path
        nodir:
        on error, notfound, escape default
    enditem
    button after, same, 3 Prompt: "?"  do
        ShowMessage(
            "The polygon layer defines the region to update. Only links " +
            "within the polygon are updated."
        )
    enditem

    // Create map
    button 16, 9, 20 Prompt: "Create Map"  do
        if old_dbd = null then Throw("Choose the original link layer")
        if new_dbd = null then Throw("Choose the new link layer")
        if poly_dbd = null then Throw("Choose the polygon layer that defines the region to be updated.")

        // Close the check map if it is open
        {maps, , } = GetMaps()
        if maps.position(check_map) <> 0 then CloseMap(check_map)

        merge = CreateObject("MergeTool", {
            OldDBD: old_dbd,
            NewDBD: new_dbd,
            PolyDBD: poly_dbd
        })
        check_map = merge.CreateMap()
    enditem
    button after, same, 3 Prompt: "?"  do
        ShowMessage(
            "This step is not required, but is useful to check that input " +
            "arguments are set correctly."
        )
    enditem

    // Quit Button
    button 1, 13, 10 Prompt:"Quit" do
        Return(1)
    enditem

    // Help Button
    button 22, same, 10 Prompt:"Help" do
        ShowMessage(
            "The master link layer is managed jointly by DCHC MPO and CAMPO. " +
            "This often requires them to make edits at the same time. This " + 
            "tool makes it easier to merge those disparate edits back " +
            "together.\n\n" +
            "Point the tool to the original link layer to update, the new " +
            "link layer with updated attributes/geography, and a polygon " +
            "defining the subarea within which to update. Click Merge.\n\n" +
            "The tool does not modify any of the layers. Instead, a new " +
            "geographic file is created in a 'merge_output' folder in the " +
            "same directory as the original link layer."
        )
    enditem


    // Merge Button
    button 42, same, 10 Prompt:"Merge" do
        if old_dbd = null then Throw("Choose the original link layer")
        if new_dbd = null then Throw("Choose the new link layer")
        if poly_dbd = null then Throw("Choose the polygon layer that defines the region to be updated.")

        // Close the check map if it is open
        {maps, , } = GetMaps()
        if maps.position(check_map) <> 0 then CloseMap(check_map)

        merge = CreateObject("MergeTool", {
            OldDBD: old_dbd,
            NewDBD: new_dbd,
            PolyDBD: poly_dbd
        })
        merge.Replace()

        ShowMessage(
            "Merge finished.\nA new folder named 'merge_output' has been " + 
            "created next to the original link layer. Find the results there."
        )
    enditem

enddbox

/*

*/

Macro "test merge"
    merge = CreateObject("MergeTool", {
        OldDBD: "C:\\projects\\TRM\\trm_project\\repo_trmg2\\master\\networks\\master_links.dbd",
        // NewDBD: "C:\\projects\\TRM\\trm_project\\working_files\\client_data\\2020\\campo_data\\master_links.dbd",
        // PolyDBD: "C:\\projects\\TRM\\trm_project\\working_files\\client_data\\2020\\campo_poly\\campo_poly.dbd"
        NewDBD: "C:\\projects\\TRM\\trm_project\\working_files\\client_data\\2020\\dchc_data\\master_links.dbd",
        PolyDBD: "C:\\projects\\TRM\\trm_project\\working_files\\client_data\\2020\\dchc_data\\dchc_poly.dbd"
    })
    merge.Replace()
endmacro

Class "MergeTool" (MacroOpts)

    init do
        self.OldDBD = MacroOpts.OldDBD
        self.NewDBD = MacroOpts.NewDBD
        self.PolyDBD = MacroOpts.PolyDBD
    enditem

    Macro "Replace" (MacroOpts) do

        if MacroOpts.OldDBD <> null then self.OldDBD = MacroOpts.OldDBD
        if MacroOpts.NewDBD <> null then self.NewDBD = MacroOpts.NewDBD
        if MacroOpts.PolyDBD <> null then self.PolyDBD = MacroOpts.PolyDBD

        if self.OldDBD = null then Throw("Replace: 'OldDBD' is null")
        if self.NewDBD = null then Throw("Replace: 'NewDBD' is null")
        if self.PolyDBD = null then Throw("Replace: 'PolyDBD' is null")

        old_dbd = self.OldDBD
        new_dbd = self.NewDBD
        poly_dbd = self.PolyDBD

        {drive, path, name, ext} = SplitPath(self.OldDBD)
        out_dir = drive + path + "merge_output"
        if GetDirectoryInfo(out_dir, "All") = null then CreateDirectory(out_dir)
        out_dbd = out_dir + "/" + name + ext

        // Create map with all three DBDs
        {old_nlyr, old_llyr} = GetDBLayers(old_dbd)
        map = RunMacro("G30 new map", self.OldDBD)
        window = GetWindowName()
        MinimizeWindow(window)
        {new_nlyr, new_llyr} = GetDBLayers(new_dbd)
        new_llyr = AddLayer(map, new_llyr, new_dbd, new_llyr)
        new_nlyr = AddLayer(map, new_nlyr, new_dbd, new_nlyr)
        {plyr} = GetDBLayers(poly_dbd)
        plyr = AddLayer(map, plyr, poly_dbd, plyr)

        // Export old links not inside polygon to a new dbd
        SetLayer(old_llyr)
        n = SelectByVicinity(
            "sel", "several", plyr + "|", 0,
            {Inclusion: "Intersecting"}
        )
        if n = 0 then Throw("Replace: your polygon does not intersect any links")
        SetInvert("sel", "sel")
        {, link_specs} = GetFields(old_llyr, "All")
        {, node_specs} = GetFields(old_nlyr, "All")
        ExportGeography(old_llyr + "|sel", out_dbd, {
            "Field Spec": link_specs,
            "Node Field Spec": node_specs,
            "Layer Name": old_llyr,
            "Node Name": old_nlyr
        })

        // Export new links inside polygon to a new dbd
        SetLayer(new_llyr)
        n = SelectByVicinity(
            "sel", "several", plyr + "|", 0,
            {Inclusion: "Intersecting"}
        )
        if n = 0 then Throw("Replace: your polygon does not intersect any links")
        {, link_specs} = GetFields(new_llyr, "All")
        {, node_specs} = GetFields(new_nlyr, "All")
        sub_dbd = out_dir + "/subarea.dbd"
        ExportGeography(new_llyr + "|sel", sub_dbd, {
            "Field Spec": link_specs,
            "Node Field Spec": node_specs,
            "Layer Name": old_llyr,
            "Node Name": old_nlyr
        })
        CloseMap(map)

        // Merge two pieces
        {out_nlyr, out_llyr} = GetDBLayers(out_dbd)
        map = RunMacro("G30 new map", out_dbd)
        window = GetWindowName()
        MinimizeWindow(window)
        {sub_nlyr, sub_llyr} = GetDBLayers(sub_dbd)
        sub_nlyr = AddLayer(map, sub_nlyr, sub_dbd, sub_nlyr)
        sub_llyr = AddLayer(map, sub_llyr, sub_dbd, sub_llyr)
        {link_fields, } = GetFields(out_llyr, "All")
        for link_field in link_fields do
            if link_field = "ID" then continue
            if link_field = "Dir" then continue
            if link_field = "Length" then continue
            l_fields = l_fields + {{link_field, link_field}}
        end
        {node_fields, } = GetFields(out_nlyr, "All")
        for node_field in node_fields do
            if node_field = "ID" then continue
            if node_field = "Longitude" then continue
            if node_field = "Latitude" then continue
            if node_field = "Elevation" then continue
            n_fields = n_fields + {{node_field, node_field}}
        end
        MergeGeography(out_llyr, sub_llyr + "|", {
            {"Fields", l_fields},
            {"Node Fields", n_fields},
            {"Snap", "true"},
            {"ID", "true", 0}
        })
        
        CloseMap(map)
        DeleteDatabase(sub_dbd)
    enditem

    Macro "CreateMap" (MacroOpts) do
        
        old_dbd = self.OldDBD
        new_dbd = self.NewDBD
        poly_dbd = self.PolyDBD

        {check_map, {new_nlyr, new_llyr}} = RunMacro("Create Map", {File: new_dbd, minimized: "false"})
        new_nlyr = RenameLayer(new_nlyr, "new node", )
        new_llyr = RenameLayer(new_llyr, "new links", )

        // Add layers
        {old_nlyr, old_llyr} = GetDBLayers(old_dbd)
        old_nlyr = AddLayer(check_map, old_nlyr, old_dbd, old_nlyr, )
        old_llyr = AddLayer(check_map, old_llyr, old_dbd, old_llyr, )
        RunMacro("G30 new layer default settings", new_nlyr)
        RunMacro("G30 new layer default settings", new_llyr)
        old_nlyr = RenameLayer(old_nlyr, "original node", )
        old_llyr = RenameLayer(old_llyr, "original links", )
        {plyr} = GetDBLayers(poly_dbd)
        plyr = AddLayer(check_map, plyr, poly_dbd, plyr, )
        RunMacro("G30 new layer default settings", old_nlyr)
        RunMacro("G30 new layer default settings", old_llyr)
        plyr = RenameLayer(plyr, "polygon", )
        
        // Colors/Styles
        SetLineColor(new_llyr + "|", ColorRGB(0, 0, 65535))
        SetLineColor(plyr + "|", ColorRGB(65535, 0, 0))
        SetLineWidth(plyr + "|", 3)
        SetLayerVisibility(check_map + "|" + old_nlyr, "false")
        SetLayerVisibility(check_map + "|" + new_nlyr, "false")
        SetLayer(old_llyr)

        return(check_map)
    enditem
endclass