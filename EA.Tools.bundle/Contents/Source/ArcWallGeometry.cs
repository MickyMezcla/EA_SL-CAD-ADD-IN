using System;
using System.Collections.Generic;
using System.Globalization;
using System.Text;

namespace ProkonArcWall
{
    public struct Vertex
    {
        public double X, Y, Bulge;
        public Vertex(double x, double y, double bulge) { X = x; Y = y; Bulge = bulge; }
    }

    public struct XY
    {
        public double X, Y;
        public XY(double x, double y) { X = x; Y = y; }
    }

    public static class ArcWallGeometry
    {
        public const int MaxPoints = 5000;
        // Leave a margin for rounding the final WCS output to six decimal mm.
        public const double RoundingMargin = 0.000002;

        public static List<XY> Sample(IList<Vertex> vertices, double tolerance)
        {
            if (!Finite(tolerance) || tolerance <= RoundingMargin)
                throw new ArgumentException("Tolerance must be greater than 0.000002 mm.");
            if (vertices == null || vertices.Count < 2)
                throw new ArgumentException("The outline has too few vertices.");
            var result = new List<XY>();
            double allowed = tolerance - RoundingMargin;
            for (int i = 0; i < vertices.Count; i++)
            {
                Vertex p = vertices[i], q = vertices[(i + 1) % vertices.Count];
                if (!Finite(p.X) || !Finite(p.Y) || !Finite(p.Bulge))
                    throw new ArgumentException("The outline contains an invalid coordinate.");
                double dx = q.X - p.X, dy = q.Y - p.Y;
                double chord = Math.Sqrt(dx * dx + dy * dy);
                if (chord < 0.000001)
                {
                    if (Math.Abs(p.Bulge) > 1e-14)
                        throw new ArgumentException("A zero-length segment has a nonzero arc bulge.");
                    continue; // Repeated closing vertex is harmless.
                }
                Add(result, new XY(p.X, p.Y));
                if (p.Bulge == 0) continue;
                double b = p.Bulge, ab = Math.Abs(b);
                double radius = chord * 0.25 * (ab + 1.0 / ab);
                double theta = 4.0 * Math.Atan(b);
                if (!Finite(radius) || radius <= 0)
                    throw new ArgumentException("The arc radius is outside the supported numeric range.");
                double maxAngle = allowed >= radius ? Math.PI / 2.0
                    : Math.Min(Math.PI / 2.0, 4.0 * Math.Atan(Math.Sqrt(allowed / (2.0 * radius - allowed))));
                double steps = Math.Ceiling(Math.Abs(theta) / maxAngle);
                if (!Finite(steps) || steps > MaxPoints)
                    throw new ArgumentException("Too many coordinates. Increase the tolerance (maximum 5000 rows).");
                int n = Math.Max(1, (int)steps);
                // Use a chord-local frame to avoid subtracting a distant arc centre.
                // cos(t)-1 = -2 sin(t/2)^2 remains stable for shallow arcs.
                double offset = chord * (1.0 / b - b) / 4.0;
                for (int j = 1; j < n; j++)
                {
                    double t = theta * j / n, sin = Math.Sin(t);
                    double cm1 = -2.0 * Math.Pow(Math.Sin(t / 2.0), 2);
                    double u = -chord * cm1 / 2.0 + offset * sin;
                    double v = -chord * sin / 2.0 - offset * cm1;
                    Add(result, new XY(p.X + u * dx / chord - v * dy / chord,
                                       p.Y + u * dy / chord + v * dx / chord));
                }
            }
            if (result.Count < 3) throw new ArgumentException("The outline does not enclose an area.");
            return result;
        }

        private static void Add(List<XY> points, XY p)
        {
            if (!Finite(p.X) || !Finite(p.Y)) throw new ArgumentException("Invalid sampled coordinate.");
            if (points.Count >= MaxPoints)
                throw new ArgumentException("Too many coordinates. Increase the tolerance (maximum 5000 rows).");
            points.Add(p);
        }

        public static double Area(IList<XY> points)
        {
            double sum = 0, ox = points[0].X, oy = points[0].Y;
            for (int i = 0; i < points.Count; i++)
            {
                XY a = points[i], b = points[(i + 1) % points.Count];
                sum += (a.X - ox) * (b.Y - oy) - (b.X - ox) * (a.Y - oy);
            }
            return Math.Abs(sum) / 2.0;
        }

        public static void Validate(IList<XY> p)
        {
            if (p.Count < 3 || Area(p) < 1e-8)
                throw new ArgumentException("The outline has zero area.");
            for (int i = 0; i < p.Count; i++)
            {
                XY a = p[i], b = p[(i + 1) % p.Count];
                if (Math.Abs(a.X - b.X) < 1e-9 && Math.Abs(a.Y - b.Y) < 1e-9)
                    throw new ArgumentException("The exported outline has a collapsed segment. Use a larger tolerance or repair the polyline.");
                for (int j = i + 1; j < p.Count; j++)
                {
                    if (j == i + 1 || (i == 0 && j == p.Count - 1)) continue;
                    if (Intersects(a, b, p[j], p[(j + 1) % p.Count]))
                        throw new ArgumentException("The exported outline crosses or touches itself. Repair the polyline, or reduce the tolerance.");
                }
            }
        }

        private static double Cross(XY a, XY b, XY c)
        { return (b.X - a.X) * (c.Y - a.Y) - (b.Y - a.Y) * (c.X - a.X); }

        private static bool Intersects(XY a, XY b, XY c, XY d)
        {
            const double eps = 1e-9;
            if (Math.Max(a.X, b.X) < Math.Min(c.X, d.X) - eps ||
                Math.Max(c.X, d.X) < Math.Min(a.X, b.X) - eps ||
                Math.Max(a.Y, b.Y) < Math.Min(c.Y, d.Y) - eps ||
                Math.Max(c.Y, d.Y) < Math.Min(a.Y, b.Y) - eps) return false;
            double x = Cross(a, b, c), y = Cross(a, b, d), z = Cross(c, d, a), w = Cross(c, d, b);
            return ((x >= -eps && y <= eps) || (y >= -eps && x <= eps)) &&
                   ((z >= -eps && w <= eps) || (w >= -eps && z <= eps));
        }

        public static string Format(IList<XY> points, bool opening)
        {
            var text = new StringBuilder();
            for (int i = 0; i < points.Count; i++)
            {
                if (i > 0) text.Append("\r\n");
                text.Append(i == 0 ? (opening ? "-" : "+") : "L");
                text.Append('\t').Append(Number(points[i].X));
                text.Append('\t').Append(Number(points[i].Y));
            }
            return text.ToString();
        }

        public static double Round(double value) { return Math.Round(value, 6, MidpointRounding.AwayFromZero); }
        private static string Number(double value)
        { return (Math.Abs(value) < 0.0000005 ? 0 : value).ToString("0.######", CultureInfo.InvariantCulture); }
        private static bool Finite(double value) { return !double.IsNaN(value) && !double.IsInfinity(value); }
    }
}

