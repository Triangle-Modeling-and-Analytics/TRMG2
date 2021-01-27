
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

MenuItem "MSA Feedback Menu Item" text: "MSA Feedback Model"
    menu "MSA Feedback Menu"

menu "MSA Feedback Menu"
    init do
    enditem

    MenuItem "Show Map" text: "Show Map"
        do 
        mr = CreateObject("Model.Runtime")
        result = mr.OpenFile("HWYDB")
        enditem 

    MenuItem "Show Matrix" text: "Show Matrix"
        do 
        mr = CreateObject("Model.Runtime")
        result = mr.OpenFile("GravityOutput")
        enditem 

    MenuItem "Show Matrix" text: "Show Table"
        do 
        mr = CreateObject("Model.Runtime")
        result = mr.OpenFile("Assign_FlowTable")
        enditem 


endMenu 
