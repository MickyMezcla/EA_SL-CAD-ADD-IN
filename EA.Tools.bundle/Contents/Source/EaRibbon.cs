using System;
using System.IO;
using System.Windows;
using System.Windows.Input;
using System.Windows.Media;
using Autodesk.AutoCAD.Runtime;
using Autodesk.Windows;
using AcApp = Autodesk.AutoCAD.ApplicationServices.Core.Application;

[assembly: ExtensionApplication(typeof(EaTools.EaRibbon))]

namespace EaTools
{
    public sealed class EaRibbon : IExtensionApplication
    {
        private const string TabId = "EA_TOOLS_TAB";

        public void Initialize() { AcApp.Idle += AddRibbon; }
        public void Terminate() { AcApp.Idle -= AddRibbon; }

        private static void AddRibbon(object sender, EventArgs e)
        {
            var ribbon = ComponentManager.Ribbon;
            if (ribbon == null) return;
            AcApp.Idle -= AddRibbon;
            foreach (RibbonTab existing in ribbon.Tabs)
                if (existing.Id == TabId) return;

            var tab = new RibbonTab { Id = TabId, Title = "EA Tools" };
            AddPanel(tab, "PROKON",
                Button("CAD2PROKON", "Points to\nPROKON", "CAD_POINTS_TO_PROKON.lsp",
                    "Copy reinforcement points with a selectable export origin.", 0),
                Button("COVER2BARPOINTS", "Cover to\nBar Points", "WALL_TO_PROKON.lsp",
                    "Offset the covering curve and create reinforcement points.", 1),
                Button("WALLSHAPE2PROKON", "Wall Shape\nto PROKON", "WALL_TO_PROKON.lsp",
                    "Copy a straight wall outline to PROKON.", 2),
                Button("WALLARC2PROKON", "Arc Wall Shape\nto PROKON", null,
                    "Copy a closed wall outline with arcs to PROKON.", 3));
            AddPanel(tab, "Column",
                Button("COLUMNDRAW", "Draw\nColumn", "ColumnTools.lsp",
                    "Draw a column section with reinforcement, stirrup and 601 dimensions.", 4),
                Button("CLINKDRAW", "Draw\nC-Link", "ColumnTools.lsp",
                    "Draw a C-link between two bar centres or set the outer stirrup diameter.", 5),
                Button("POINTS2REBAR", "Points to\nRebar", "ColumnTools.lsp",
                    "Draw a circle and a solid hatch at each selected reinforcement point.", 6));
            ribbon.Tabs.Add(tab);
        }

        private static void AddPanel(RibbonTab tab, string name, params RibbonButton[] buttons)
        {
            var source = new RibbonPanelSource { Title = name };
            foreach (var button in buttons) source.Items.Add(button);
            tab.Panels.Add(new RibbonPanel { Source = source });
        }

        private static RibbonButton Button(string command, string label, string lisp, string tip, int icon)
        {
            return new RibbonButton
            {
                Id = "EA_" + command, Text = label, ShowText = true, ShowImage = true,
                Size = RibbonItemSize.Large,
                Orientation = System.Windows.Controls.Orientation.Vertical,
                Image = CreateIcon(icon, 16), LargeImage = CreateIcon(icon, 32),
                ToolTip = tip, CommandHandler = new RunCommand(command, lisp)
            };
        }

        internal static ImageSource CreateIcon(int icon, int size)
        {
            var outline = new SolidColorBrush(Color.FromRgb(231, 238, 245));
            var accent = new SolidColorBrush(icon == 4 || icon == 5 ? Color.FromRgb(255, 196, 94) : Color.FromRgb(69, 219, 235));
            var ink = new Pen(outline, 1.6) { StartLineCap = PenLineCap.Round, EndLineCap = PenLineCap.Round, LineJoin = PenLineJoin.Round };
            var highlight = new Pen(accent, 2.0) { StartLineCap = PenLineCap.Round, EndLineCap = PenLineCap.Round, LineJoin = PenLineJoin.Round };
            var drawing = new DrawingGroup();
            using (var dc = drawing.Open())
            {
                dc.PushTransform(new ScaleTransform(size / 32.0, size / 32.0));
                dc.DrawRoundedRectangle(new SolidColorBrush(Color.FromRgb(33, 48, 63)), null,
                    new Rect(0, 0, 32, 32), 6, 6);
                switch (icon)
                {
                    case 0:
                        Dot(dc, accent, 8, 9); Dot(dc, accent, 8, 16); Dot(dc, accent, 8, 23);
                        Stroke(dc, ink, "M 14,16 L 25,16 M 21,12 L 25,16 L 21,20");
                        break;
                    case 1:
                        Stroke(dc, ink, "M 5,8 L 27,8 M 5,13 L 27,13");
                        Stroke(dc, highlight, "M 5,22 L 27,22");
                        Dot(dc, outline, 8, 22); Dot(dc, outline, 16, 22); Dot(dc, outline, 24, 22);
                        break;
                    case 2:
                        Stroke(dc, highlight, "M 6,7 L 12,7 L 12,20 L 26,20 L 26,26 L 6,26 Z");
                        break;
                    case 3:
                        Stroke(dc, highlight, "M 6,23 Q 6,7 25,7 L 25,13 Q 12,13 12,23 Z");
                        break;
                    case 4:
                        dc.DrawRectangle(null, ink, new Rect(7, 6, 20, 20));
                        dc.DrawRoundedRectangle(null, highlight, new Rect(10, 9, 14, 14), 2, 2);
                        Dot(dc, outline, 13, 12); Dot(dc, outline, 21, 12);
                        Dot(dc, outline, 13, 20); Dot(dc, outline, 21, 20);
                        break;
                    case 5:
                        Stroke(dc, highlight, "M 11,19 L 7,23 Q 4,26 7,28 Q 10,30 13,27 L 26,13 Q 29,10 26,7 Q 23,4 20,7 L 16,11");
                        Dot(dc, outline, 10, 25); Dot(dc, outline, 23, 10);
                        break;
                    case 6:
                        Dot(dc, outline, 6, 10); Dot(dc, outline, 6, 22);
                        Stroke(dc, ink, "M 11,16 L 17,16 M 14,13 L 17,16 L 14,19");
                        dc.DrawEllipse(accent, ink, new Point(24, 16), 4.5, 4.5);
                        break;
                }
                dc.Pop();
            }
            var image = new DrawingImage(drawing);
            image.Freeze();
            return image;
        }

        private static void Stroke(DrawingContext dc, Pen pen, string path)
        {
            dc.DrawGeometry(null, pen, Geometry.Parse(path));
        }

        private static void Dot(DrawingContext dc, Brush brush, double x, double y)
        {
            dc.DrawEllipse(brush, null, new Point(x, y), 1.6, 1.6);
        }

        private sealed class RunCommand : ICommand
        {
            private readonly string command;
            private readonly string lisp;

            public RunCommand(string command, string lisp) { this.command = command; this.lisp = lisp; }
            public event EventHandler CanExecuteChanged { add { } remove { } }
            public bool CanExecute(object parameter) { return AcApp.DocumentManager.MdiActiveDocument != null; }

            public void Execute(object parameter)
            {
                var doc = AcApp.DocumentManager.MdiActiveDocument;
                if (doc == null) return;
                if (lisp == null)
                {
                    doc.SendStringToExecute(command + " ", true, false, false);
                    return;
                }
                var directory = Path.GetDirectoryName(typeof(EaRibbon).Assembly.Location);
                var path = Path.GetFullPath(Path.Combine(directory, "..", "Lisp", lisp));
                if (!File.Exists(path))
                {
                    doc.Editor.WriteMessage("\nEA Tools: file not found: " + path);
                    return;
                }
                doc.SendStringToExecute("(progn (load \"" + path.Replace('\\', '/') +
                    "\") (c:" + command + "))\n", true, false, false);
            }
        }
    }
}
