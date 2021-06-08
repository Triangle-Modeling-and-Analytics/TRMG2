Macro "Model.Attributes"

Attributes = {{"BannerHeight",80},
                  {"BannerWidth",2000},
                  {"BannerPicture","src\\flow_chart\\bmp\\banner.bmp"},
                  {"HideBanner",0},
                  {"Base Scenario Name","Base 2016"},
                  {"ClearLogFiles",1},
                  {"CodeUI","src\\trmg2.dbd"},
                  {"ExpandStages","Side by Side"},
                  {"MaxProgressBars",2},
                  {"MinItemSpacing",20},
                  {"Output Folder Format","Output Folder\\Scenario Name"},
                  {"Output Folder Parameter","Output Folder"},
                  {"Output Folder Per Run","No"},
                  {"Picture","bmp\\TransCAD_Model.bmp"},
                  {"ReportAfterStep",0},
                  {"Requires",{{"Program","TransCAD"},
                  {"Version",9},
                  {"Build",32650}}},
                  {"Shape","Rectangle"},
                  {"Time Stamp Format","yyyyMMdd_HHmm"}}


endMacro 

Macro "Model.Step" (Args,Result)
    Attributes = {{"FrameColor",{255,255,255}},
                  {"Height",45},
                  {"PicturePosition","CenterRight"},
                  {"TextFont","Calibri|12|400|000000|0"},
                  {"Width",225}}
EndMacro


Macro "Model.Arrow" (Args,Result)
    Attributes = {{"ArrowHead","Triangle"},
                  {"ArrowHeadSize",8}}
EndMacro



/**
    Return an option array of parameters that will be stored in the Args array at runtime
**/
// if needed, can email status at every step
Macro "Model.OnStepDone" (Args,Result,StepName)
Body:
    // RunMacro("SendMail", Args, "MSA Model Checkpoint", StepName)
    return(1)
EndMacro


// when the model is done, email the summary report
Macro "Model.OnModelDone" (Args,Result,CompletedSteps)
Body:

    rep = Args.[Report File]
    xsl = "report.xsl"
    // convert the XML report to a HTML file
    BodyFile = RunMacro("XML2HTML", rep, xsl, )
    // RunMacro("SendMail", Args, "MSA Model Report", , BodyFile)
    return(1)
EndMacro


Macro "Model.OnModelStart" (Args,Result)
Body:
    on error do
        Args.SendEmails = 0
        goto skipemails
    end

    // check if user wants to send emails at checkpoints.
    if Args.SendEmails <> 0 then do 
        ServerName = Args.[SMTPServer]
        PortNumber = Args.PortNumber

        // configure mail client
        if Args.mailObj = null then do
            mail = CreateObject("Utilities.Mail", {Server: ServerName, Port: PortNumber})
            mail.UseDefaultCredentials = false
            mail.ResetCredentials() // every time the model is launched, reset the credentials. If credentials are needed a dbox will popup
            end
        end
    skipemails:
    on error default

    scenario_created = RunMacro("Check Scenario Creation", Args)
    if !scenario_created then Throw("Scenario not created")

    Return(Runtime_Args)
EndMacro

macro "Model.OnModelLoad" (Args, Results)
Body:
    flowchart = RunMacro("GetFlowChart")
    { drive , path , name , ext } = SplitPath(flowchart.UI)
    rootFolder = drive + path

    ui_DB = rootFolder + "src\\trmg2.dbd"
    srcFile = rootFolder + "src\\_TRMCompile.lst"
    RunMacro("CompileGISDKCode", {Source: srcFile, UIDB: ui_DB, Silent: 0, ErrorMessage: "Error compiling code"})
endmacro 

Macro "Model.OnModelReady" (Args,Result)
Body:

    // on error do
    //     on error default
    // end

    // mail = CreateObject("Utilities.Mail", {Server: ServerName, Port: PortNumber})
    // mail.UseDefaultCredentials = false
    // mail.ResetCredentials() // every time the model is launched, reset the credentials. If credentials are needed a dbox will popup

    Return()
EndMacro

/*
This macro checks that the current scenario is created. If not, it prompts the
user to create it. As a special case, the base scenario ("base_2016") is simply
created without prompting.

Returns true if the scenario is already created or is created by the macro.
Returns false otherwise.
*/

Macro "Check Scenario Creation" (Args)

    mr = CreateObject("Model.Runtime")
    Args = mr.GetValues()
    scen_dir = Args.[Scenario Folder]
    {, scen_name} = mr.GetScenario()
    files_to_check = {
        Args.[Input Links],
        Args.[Input Routes],
        Args.[Input SE]
    }

    scenario_created = "true"
    for file in files_to_check do
        if GetFileInfo(file) = null then scenario_created = "false"
    end
    if scenario_created then return("true")

    // Ensure the minimum files are present
    if GetDirectoryInfo(scen_dir, "All") = null then Throw(
        "The scenario directory does not exist.\n" +
        "Scenario Directory: \n" +
        scen_dir
    )
    else if GetFileInfo(scen_dir + "/RoadwayProjectList.csv") = null then Throw(
        "The scenario directory is missing RoadwayProjectList.csv"
    )
    else if GetFileInfo(scen_dir + "/TransitProjectList.csv") = null then Throw(
        "The scenario directory is missing TransitProjectList.csv"
    )

    // Ask to create scenario. If it's the base scenario, just create it.
    yesno = MessageBox(
        "The scenario has not been created\n(TRMG2 Menu -> Create Scenario)\n" +
        "Would you like to create the scenario? After creation, you will be " +
        "prompted to continue running the model.",
        {Buttons: "YesNo"}
    )
    if yesno = "Yes" then do
        mr.RunCode("Create Scenario", Args)
        return("true")
    end else return("false")
endmacro