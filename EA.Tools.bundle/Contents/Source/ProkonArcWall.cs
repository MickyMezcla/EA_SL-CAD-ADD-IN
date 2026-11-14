using System;
using System.Collections.Generic;
using Autodesk.AutoCAD.ApplicationServices;
using Autodesk.AutoCAD.DatabaseServices;
using Autodesk.AutoCAD.EditorInput;
using Autodesk.AutoCAD.Geometry;
using Autodesk.AutoCAD.Runtime;
using AcApp = Autodesk.AutoCAD.ApplicationServices.Core.Application;

[assembly: CommandClass(typeof(ProkonArcWall.Plugin))]

namespace ProkonArcWall
{
    public sealed class Plugin
    {
        [CommandMethod("WALLARC2PROKON", CommandFlags.Modal)]
        public static void CopyWall()
        {
            Document doc = AcApp.DocumentManager.MdiActiveDocument;
            if (doc == null) return;
            Editor ed = doc.Editor;
            try
            {
                var pick = new PromptEntityOptions("\nSelect ONE joined CLOSED wall outline polyline (drawing units: mm): ");
                pick.SetRejectMessage("\nSelect a lightweight 2D polyline. JOIN and CLOSE the outline first.");
                pick.AddAllowedClass(typeof(Polyline), true);
                PromptEntityResult chosen = ed.GetEntity(pick);
                if (chosen.Status != PromptStatus.OK) return;
                List<XY> points;
                int sourceVertices;
                using (Transaction tr = doc.Database.TransactionManager.StartOpenCloseTransaction())
                {
                    var pl = (Polyline)tr.GetObject(chosen.ObjectId, OpenMode.ForRead);
                    if (!pl.Closed) { ed.WriteMessage("\nNot copied: polyline is OPEN. Use PEDIT > Join > Close, then retry."); return; }
                    if (Math.Abs(pl.Normal.X) > 1e-10 || Math.Abs(pl.Normal.Y) > 1e-10)
                    { ed.WriteMessage("\nNot copied: outline must be parallel to the WCS XY plane. Tilted/3D walls are not supported."); return; }
                    if (Math.Abs(pl.Thickness) > 1e-9)
                    { ed.WriteMessage("\nNot copied: polyline thickness must be zero. Select the planar boundary."); return; }
                    for (int i = 0; i < pl.NumberOfVertices; i++)
                        if (Math.Abs(pl.GetStartWidthAt(i)) > 1e-9 || Math.Abs(pl.GetEndWidthAt(i)) > 1e-9)
                        { ed.WriteMessage("\nNot copied: polyline has display width. Select the actual zero-width concrete boundary."); return; }
                    var options = new PromptDoubleOptions("\nMaximum arc chord deviation in mm (required, e.g. 0.25): ") {
                        AllowNone = false, AllowNegative = false, AllowZero = false, UseDefaultValue = false
                    };
                    PromptDoubleResult tolerance = ed.GetDouble(options);
                    if (tolerance.Status != PromptStatus.OK) return;
                    var vertices = new List<Vertex>();
                    sourceVertices = pl.NumberOfVertices;
                    for (int i = 0; i < pl.NumberOfVertices; i++)
                    {
                        Point2d p = pl.GetPoint2dAt(i);
                        vertices.Add(new Vertex(p.X, p.Y, pl.GetBulgeAt(i)));
                    }
                    List<XY> ocs = ArcWallGeometry.Sample(vertices, tolerance.Value);
                    Matrix3d ecs = pl.Ecs;
                    points = new List<XY>();
                    foreach (XY p in ocs)
                    {
                        // Polyline.Ecs supplies the OCS orientation; elevation is the OCS Z.
                        Point3d w = new Point3d(p.X, p.Y, pl.Elevation).TransformBy(ecs);
                        points.Add(new XY(ArcWallGeometry.Round(w.X), ArcWallGeometry.Round(w.Y)));
                    }
                    ArcWallGeometry.Validate(points);
                }
                var kind = new PromptKeywordOptions("\nBoundary type");
                kind.Keywords.Add("Concrete");
                kind.Keywords.Add("Opening");
                kind.AllowNone = false;
                PromptResult selected = ed.GetKeywords(kind);
                if (selected.Status != PromptStatus.OK) return;
                string text = ArcWallGeometry.Format(points, selected.StringResult == "Opening");
                // Persistent Unicode clipboard; no shell, temporary file, or drawing edits.
                System.Windows.Forms.Clipboard.SetDataObject(text, true, 5, 100);
                ed.WriteMessage("\nCopied {0} rows from {1} vertices; area = {2:0.###} mm2. WCS XY, millimetres.",
                    points.Count, sourceVertices, ArcWallGeometry.Area(points));
                ed.WriteMessage("\nPROKON General Column: select an empty Code cell in COLUMN SECTION and press Ctrl+V.");
                ed.WriteMessage("\nOnly this boundary was copied. No reinforcement or loads were generated.");
            }
            catch (System.Exception ex) { ed.WriteMessage("\nArc Wall export stopped: " + ex.Message); }
        }

    }
}
