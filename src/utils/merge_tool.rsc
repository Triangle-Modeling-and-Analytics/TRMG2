/*

*/

Macro "test"
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
endclass