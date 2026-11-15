"""Rellena el campo 'events' del manifiesto de arte (data/victoria_mode/content/core/art_manifest.json)
con los eventos de todos los paquetes de contenido que usan cada art_key, e informa de claves desconocidas
o sin uso. Uso (desde la raíz del repositorio):

    python tools/art_manifest.py            # actualiza el manifiesto y muestra el resumen
    python tools/art_manifest.py --check    # solo comprueba (código 1 si hay claves desconocidas)

El manifiesto es la lista de encargos para generar ilustraciones por lotes: una imagen por categoría,
compartida por todos los eventos que la usan (res://assets/events/<art_key>.png).
"""
import glob
import json
import sys

CONTENT = "data/victoria_mode/content/"
MANIFEST = CONTENT + "core/art_manifest.json"


def main() -> int:
    check_only = "--check" in sys.argv
    man = json.load(open(MANIFEST, encoding="utf-8"))
    keys = {c["art_key"]: c for c in man["categories"]}
    uses = {k: [] for k in keys}
    unknown = []
    for f in sorted(glob.glob(CONTENT + "*/events/*.json")):
        for e in json.load(open(f, encoding="utf-8")).get("events", []):
            art = e.get("art", "")
            if art == "":
                continue
            if art not in keys:
                unknown.append((e["id"], art))
            else:
                uses[art].append(e["id"])
    for k, c in keys.items():
        c["events"] = sorted(uses[k])
    for eid, art in unknown:
        print("art_key desconocido: %s → %s" % (eid, art))
    total = sum(len(v) for v in uses.values())
    print("%d categorías visuales · %d eventos con ilustración · %d sin uso" % (len(keys), total, sum(1 for v in uses.values() if not v)))
    for k in keys:
        print("  %-20s %3d" % (k, len(uses[k])))
    if not check_only:
        lines = ["{"]
        lines.append(' "_doc": %s,' % json.dumps(man["_doc"], ensure_ascii=False))
        lines.append(' "style": %s,' % json.dumps(man["style"], ensure_ascii=False))
        lines.append(' "categories": [')
        for i, c in enumerate(man["categories"]):
            lines.append("  " + json.dumps(c, ensure_ascii=False) + ("," if i < len(man["categories"]) - 1 else ""))
        lines.append(" ]")
        lines.append("}")
        open(MANIFEST, "w", encoding="utf-8", newline="\n").write("\n".join(lines) + "\n")
    return 1 if unknown else 0


if __name__ == "__main__":
    sys.exit(main())
