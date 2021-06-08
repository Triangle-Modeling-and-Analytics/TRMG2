
Class "Visualize.Menu.Items"

    init do 
        self.runtimeObj = CreateObject("Model.Runtime")
    enditem 

    Macro "GetMenus" do
        Menus = {
             { ID: "ConvChart", Title: "Convergence Chart" , Macro: "Menu_ConvergenceChart" }
            ,{ ID: "FlowMap", Title: "Flow Map" , Macro: "Menu_FlowMapt" }
            ,{ ID: "M_Chord", Title: "Chord Diagram" , Macro: "Menu_Chord" }
            ,{ ID: "M_Sankey", Title: "Sankey Diagram" , Macro: "Menu_Sankey" }
            }
        
        Return(Menus)
    enditem 

    Macro "Menu_FlowMapt" do 
        opts.tableArg = self.runtimeObj.GetSelectedParamInfo().Value
        opts.FlowFields = {"AB_Flow","BA_Flow"}
        opts.vocFields = {"AB_VOC","BA_VOC"}
        opts.LineLayer = self.runtimeObj.GetValue("HWYDB")
        self.runtimeObj.RunCode("CreateFlowThemes", opts)
        enditem 

    Macro "Menu_ConvergenceChart" do 
        tableArg = self.runtimeObj.GetSelectedParamInfo().Value
        self.runtimeObj.RunCode("ConvergenceChart", {TableName: tableArg})
        enditem 

    macro "Menu_Chord" do 
        mName = self.runtimeObj.GetSelectedParamInfo().Value
        TAZGeoFile = self.runtimeObj.GetValue("TG_ZonalTable")
        self.runtimeObj.RunCode("CreateWebDiagram", {MatrixName: mName, TAZDB: TAZGeoFile, DiagramType: "Chord"})
    enditem         

    macro "Menu_Sankey" do 
        mName = self.runtimeObj.GetSelectedParamInfo().Value
        TAZGeoFile = self.runtimeObj.GetValue("TG_ZonalTable")
        self.runtimeObj.RunCode("CreateWebDiagram", {MatrixName: mName, TAZDB: TAZGeoFile, DiagramType: "Sankey"})
    enditem         

endClass 

MenuItem "TRMG2 Menu Item" text: "TRMG2"
    menu "TRMG2 Menu"

menu "TRMG2 Menu"
    init do
    enditem

    MenuItem "Create Scenario" text: "Create Scenario"
        do 
        mr = CreateObject("Model.Runtime")
        Args = mr.GetValues()
        {, scen_name} = mr.GetScenario()

        // Check that a scenario is selected and that a folder has been chosen
        if scen_name = null then do
            ShowMessage("Choose a scenario (not 'Model')")
            return()
        end
        if Args.[Scenario Folder] = null then do
            ShowMessage(
                "Choose a folder for the current scenario\n" +
                "(Parameters -> Files -> Scenario -> Input)"
            )
            return()
        end

        mr.RunCode("Create Scenario", Args)
        return(1)
    enditem

    /*
    Temporary macro to get initial congested skims. Keeping during development
    in case I need to re-run.
    TODO: delete when done
    */
    MenuItem "Cong Skim" text: "Cong Skims"
        do 
        mr = CreateObject("Model.Runtime")
        Args = mr.GetValues()
        {, scen_name} = mr.GetScenario()

        // Check that a scenario is selected and that a folder has been chosen
        if scen_name = null then do
            ShowMessage("Choose a scenario (not 'Model')")
            return()
        end
        if Args.[Scenario Folder] = null then do
            ShowMessage(
                "Choose a folder for the current scenario\n" +
                "(Parameters -> Files -> Scenario -> Input)"
            )
            return()
        end

        mr.RunCode("get cong skims", Args)
        return(1)
    enditem
endMenu 