"""Top knowledge-base similarity for each skill's trigger phrases (Inc 6 risk B4).

Embeds the KB chunks and the phrases with EmbeddingGemma-300M the way the app
does (flutter_gemma_litertlm 1.8.5 + flutter_gemma_embeddings 2.2.1):
ids = [2] + spm.encode(prefix + text) + [1], right-padded with 0 to 512; the
graph output is already pooled and normalized; similarity = cosine. Query
prefix "task: search result | query: ", document prefix "title: none | text: ".
Calibration: the golden on-topic questions score >= 0.546 and off-topic
<= 0.161 here, matching the wiring note's 0.25-0.525 safe gate range.

    fvm dart run tool/dump_kb_chunks.dart > build/kb_chunks.json
    python3 tool/measure_skill_triggers.py build/kb_chunks.json \
        ~/Work/models/embeddinggemma test_assets/skill_trigger_similarity.json

Needs ai_edge_litert, sentencepiece and numpy.
"""
import datetime
import json
import sys

import numpy as np
import sentencepiece as spm
from ai_edge_litert.interpreter import Interpreter

QUERY = "task: search result | query: "
DOC = "title: none | text: "
GATE = 0.40  # kKbMinSimilarity

PHRASES = {
    "device-info": [
        "What device am I on?",
        "Which accelerator is running?",
        "Which backends are you running on?",
        "Are you running on the GPU right now?",
        "What models are loaded and how much memory do you use?",
        "Tell me about the hardware you're running on.",
    ],
    "timer": [
        "Set a timer for 10 seconds",
        "Set a timer for 17 seconds",
        "Set a timer for 90 seconds",
        "Set a timer for 25 minutes",
        "Pasta timer, an hour and 5 minutes",
        "Start the tea timer",
        "Cancel the tea timer",
        "How long is left on my timers?",
    ],
    "current-time": [
        "What time is it?",
        "What's the date today?",
        "What day of the week is it?",
    ],
    "camera-watch": [
        "Tell me when you see a cup",
        "Watch the camera for a dog",
        "Stop watching",
    ],
}


def main(chunks_path, model_dir, out_path):
    sp = spm.SentencePieceProcessor(model_file=f"{model_dir}/sentencepiece.model")
    it = Interpreter(
        model_path=f"{model_dir}/embeddinggemma-300M_seq512_mixed-precision.tflite"
    )
    it.allocate_tensors()
    inp = it.get_input_details()[0]
    out = it.get_output_details()[0]
    seq = inp["shape"][1]

    def embed(prefix, text):
        ids = ([2] + sp.encode(prefix + text) + [1])[:seq]
        ids += [0] * (seq - len(ids))
        it.set_tensor(inp["index"], np.array([ids], dtype=inp["dtype"]))
        it.invoke()
        v = it.get_tensor(out["index"])[0].astype(np.float64)
        return v / np.linalg.norm(v)

    chunks = json.load(open(chunks_path))
    docs = np.stack([embed(DOC, c["content"]) for c in chunks])
    rows = []
    for skill, phrases in PHRASES.items():
        for q in phrases:
            sims = docs @ embed(QUERY, q)
            best = int(np.argmax(sims))
            rows.append(
                {
                    "skill": skill,
                    "q": q,
                    "top": round(float(sims[best]), 3),
                    "doc": chunks[best]["id"],
                }
            )
            print(f'{skill:13} {rows[-1]["top"]:.3f} {q!r} -> {rows[-1]["doc"]}')
    json.dump(
        {
            "measured": f"{datetime.date.today()} tool/measure_skill_triggers.py, "
            f"EmbeddingGemma-300M seq512 mixed-precision, {len(chunks)} chunks",
            "gate": GATE,
            "phrases": rows,
        },
        open(out_path, "w"),
        indent=1,
    )


if __name__ == "__main__":
    main(*sys.argv[1:4])
