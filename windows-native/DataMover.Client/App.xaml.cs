using System.Windows;
using DataMover.Core.Diagnostics;

namespace DataMover.Client;

public partial class App : Application
{
    protected override void OnStartup(StartupEventArgs e)
    {
        // Orice exceptie neprinsa ajunge in jurnalul structurat (fara date
        // personale: Redactor curata mesajul), apoi comportamentul implicit.
        DispatcherUnhandledException += (_, a) =>
            StructuredLog.Shared.Log(LogLevel.Critical, "app", "app.unhandled", "Exceptie neprinsa in interfata", error: a.Exception);
        AppDomain.CurrentDomain.UnhandledException += (_, a) =>
        {
            if (a.ExceptionObject is Exception ex) StructuredLog.Shared.Log(LogLevel.Critical, "app", "app.unhandled", "Exceptie neprinsa", error: ex);
        };
#if DEBUG
        UiTest.Parse(e.Args);
#endif
        base.OnStartup(e);
    }

    protected override void OnExit(ExitEventArgs e)
    {
        StructuredLog.Shared.Log(LogLevel.Info, "app", "app.exited", "Aplicatie inchisa");
        base.OnExit(e);
    }
}
