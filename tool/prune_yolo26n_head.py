"""Cut the in-graph NMS-free selection head (TopK/GatherND/Cast/int64) off YOLO26n.

New single output: the Detect head's [1, 8400, 84] tensor (op 410 TRANSPOSE output):
  [..., 0:4]  = x1, y1, x2, y2 in 640x640 input pixels (strides already applied)
  [..., 4:84] = per-class sigmoid scores (80 COCO classes)
Every remaining op is float32 and GPU-supported, so CompiledModel(GPU only) either fully accelerates or throws.

Usage: .venv/bin/python prune_head.py <in.tflite> <out.tflite>
"""
import sys

from ai_edge_litert.tools import flatbuffer_utils as fu

CUT_TENSOR_SUFFIX = "head.Detect_23;45"  # op 410 output, shape [1, 8400, 84]


def main(src, dst):
    m = fu.read_model(src)
    sg = m.subgraphs[0]
    names = [t.name.decode() if isinstance(t.name, bytes) else t.name for t in sg.tensors]
    cut = [i for i, n in enumerate(names) if n.endswith(CUT_TENSOR_SUFFIX)]
    assert len(cut) == 1, cut
    cut = cut[0]
    assert list(sg.tensors[cut].shape) == [1, 8400, 84], sg.tensors[cut].shape
    producer = [k for k, op in enumerate(sg.operators) if cut in list(op.outputs)]
    assert len(producer) == 1
    last = producer[0]
    # keep ops [0..last]; everything after only feeds the selection head
    sg.operators = sg.operators[: last + 1]
    sg.outputs = [cut]
    sg.tensors[cut].name = b"detections_raw"
    # The ADD opcode is shared by every ADD and carries v4 because the head had int64 ADDs.
    # LiteRT 2.1.5's Metal GPU delegate (flutter_litert 3.9.x on iOS/macOS) rejects ADD > v2,
    # which caps GPU placement at 54/411 ops. All remaining ADDs are float32 -> v1 is exact.
    FLOAT32 = 0
    for k, oc in enumerate(m.operatorCodes):
        if fu.opcode_to_name(m, k) == "ADD":
            for op in sg.operators:
                if op.opcodeIndex == k:
                    assert all(sg.tensors[i].type == FLOAT32 for i in op.inputs if i >= 0), "non-float ADD left"
            print(f"ADD opcode v{oc.version} -> v1")
            oc.version = 1
    for sd in m.signatureDefs or []:
        for o in sd.outputs:
            o.tensorIndex = cut
            o.name = b"output_0"
    fu.write_model(m, dst)
    print(f"kept {last + 1} ops, output tensor {cut} {list(sg.tensors[cut].shape)} -> {dst}")


if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2])
