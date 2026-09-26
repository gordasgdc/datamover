#!/usr/bin/env python3
"""Generează windows-native/.../DeliveryReportText.g.cs din sursa Swift a raportului
(texte RO/EN/ES, CSS, semnul de brand), ca rapoartele Mac și Windows să fie identice.
Cu --check: iese cu 1 dacă fișierul C# nu corespunde sursei Swift (folosit de preflight)."""
import re, sys, os
root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sw = open(os.path.join(root, 'mac-native/Sources/DataMoverMac/Reporting/DeliveryReport.swift'), encoding='utf-8').read()
start = sw.index('static let strings')
block = sw[start:sw.index('    ]\n', start)]
entries = re.findall(r'"([a-zA-Z.]+)": \[\.ro: "((?:[^"\\]|\\.)*)", \.en: "((?:[^"\\]|\\.)*)", \.es: "((?:[^"\\]|\\.)*)"\]', block)
if len(entries) != block.count('.ro:'):
    sys.exit("gen-report-strings: nu am putut citi toate cheile din Swift")
css = re.search(r'static let css = """\n(.*?)\n    """', sw, re.S).group(1)
css = '\n'.join(l[4:] if l.startswith('    ') else l for l in css.split('\n'))
mark = re.search(r'static let markSVG = "(.*?)"\n', sw).group(1)
lines = [f'        ["{k}"] = new[] {{ "{ro}", "{en}", "{es}" }},' for k, ro, en, es in entries]
out = f'''// GENERAT din mac-native/Sources/DataMoverMac/Reporting/DeliveryReport.swift
// (texte + CSS), ca rapoartele Mac și Windows să spună exact același lucru.
// Regenerare: scripts/gen-report-strings.py. Nu edita manual.
namespace DataMover.Core.Services;

public static partial class DeliveryReportText
{{
    public static readonly Dictionary<string, string[]> Strings = new()
    {{
{chr(10).join(lines)}
    }};

    public const string Css = """
{css}
""";

    public const string MarkSvg = "{mark}";
}}
'''
dst = os.path.join(root, 'windows-native/DataMover.Core/Services/DeliveryReportText.g.cs')
if '--check' in sys.argv:
    same = os.path.exists(dst) and open(dst, encoding='utf-8').read() == out
    print("texte raport Mac = Windows" if same else "texte raport Windows DESINCRONIZATE: rulează scripts/gen-report-strings.py")
    sys.exit(0 if same else 1)
open(dst, 'w', encoding='utf-8').write(out)
print(f"{len(entries)} chei scrise în {os.path.relpath(dst, root)}")
