#!/usr/bin/env python3
"""Dump homr's per-staff decoder symbols with their input-image positions (homr >= dda4d2f,
EncodedSymbol.image_coordinates) for comparison with `omr-test parse-page` (OMR_POSITIONS_OUT).

    PYTHONPATH=<homr checkout at dda4d2f or later> python tools/oracle/export_image_positions.py page.png out.json
"""
import json
import sys

from homr import staff_parsing
from homr.main import ProcessingConfig, process_image
from homr.music_xml_generator import XmlGeneratorArguments

captured: list[list[dict]] = []
_orig = staff_parsing.parse_staff_image


def _wrapped(*args, **kwargs):
    result = _orig(*args, **kwargs)
    captured.append([
        {"symbol": str(s), "image": list(map(float, s.image_coordinates)) if s.image_coordinates is not None else None}
        for s in result
    ])
    return result


staff_parsing.parse_staff_image = _wrapped
page, out = sys.argv[1], sys.argv[2]
config = ProcessingConfig(
    enable_debug=False, enable_cache=False, write_staff_positions=False, read_staff_positions=False,
    selected_staff=-1, transformer_use_gpu=False, segnet_use_gpu=False, coreml_encoder=False, title_detection=False,
)
process_image(page, config, XmlGeneratorArguments())
json.dump({"staffs": captured}, open(out, "w"))
print(f"{out}: {len(captured)} staffs, {sum(len(s) for s in captured)} symbols")
