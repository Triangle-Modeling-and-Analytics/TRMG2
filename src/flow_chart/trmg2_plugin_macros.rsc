
Macro "Model.Attributes" (Args,Result)
    Attributes = {
        {"BannerHeight", 90},
        {"BannerPicture", "src\\flow_chart\\bmp\\banner.jpg"},
        {"BannerWidth", 1000},
        {"Base Scenario Name", "Model"},
        {"ClearLogFiles", 0},
        {"CloseOpenFiles", 1},
        {"CodeUI", "src\\trmg2.dbd"},
        {"DebugMode", 1},
        {"ExpandStages", "Side by Side"},
        {"HideBanner", 0},
        {"MaxProgressBars", 4},
        {"MinItemSpacing", 6},
        {"Output Folder Format", "Output Folder\\Scenario Name"},
        {"Output Folder Parameter", "Output Folder"},
        {"Output Folder Per Run", "No"},
        {"Picture", "bmp\\TransCAD_Model.bmp"},
        {"ReportAfterStep", 1},
        {"Requires",
{{"Program", "TransCAD"},
{"Version", 9},
{"Build", 32895}}},
{"RunParallel", 0},
{"Shape", "Rectangle"},
{"ShowTaskMonitor", 1},
{"Time Stamp Format", "yyyyMMdd_HHmm"}
    }
EndMacro


Macro "Model.Step" (Args,Result)
    Attributes = {
        {"FrameColor",{255,255,255}},
        {"Height", 30},
        {"PicturePosition", "CenterRight"},
        {"TextFont", "Calibri|12|400|000000|0"},
        {"Width", 260}
    }
EndMacro


Macro "Model.Arrow" (Args,Result)
    Attributes = {
        {"ArrowHead", "Triangle"},
        {"ArrowHeadSize", 8},
        {"PenWidth", 1},
        {"ArrowBaseSize", 10}
    }
EndMacro


Macro "Model.OnStepStart" (Args,Result)
Body:

EndMacro


/**
    Return an option array of parameters that will be stored in the Args array at runtime
**/
// if needed, can email status at every step
Macro "Model.OnStepDone" (Args,Result,StepName)
Body:
    // RunMacro("SendMail", Args, "MSA Model Checkpoint", StepName)
    Args.SourcesObject = null
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

    Return(Runtime_Args)
EndMacro


Macro "Model.OnModelLoad" (Args, Results)
Body:
    // Compile source code
    flowchart = RunMacro("GetFlowChart")
    { drive , path , name , ext } = SplitPath(flowchart.UI)
    rootFolder = drive + path
    ui_DB = rootFolder + "src\\trmg2.dbd"
    srcFile = rootFolder + "src\\_TRMCompile.lst"
    RunMacro("CompileGISDKCode", {Source: srcFile, UIDB: ui_DB, Silent: 0, ErrorMessage: "Error compiling code"})

    if lower(GetMapUnits()) <> "miles" then
        MessageBox("Set the system to miles before running the model", {Caption: "Warning", Icon: "Warning", Buttons: "yes"})
EndMacro


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

