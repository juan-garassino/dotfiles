#!/usr/bin/env python3
"""Standalone runner for the pp-orchestrate loop."""

import argparse
import asyncio
from pathlib import Path

from promptplot.orchestrate import (
    plan_regions,
    generate_region,
    validate_chunk,
    score_chunk,
    merge_chunks,
    stream_chunk,
)
from promptplot.engine import PenState
from promptplot.config import get_config
from promptplot.llm import get_llm_provider
from promptplot.plotter import SerialPlotter, SimulatedPlotter
from promptplot.checkpoint import CheckpointManager


async def run(args):
    config = get_config()
    llm = get_llm_provider(config.llm)
    plotter = SimulatedPlotter() if args.simulate else SerialPlotter(
        port=args.port, baud_rate=config.serial.baud_rate, timeout=config.serial.timeout,
    )
    ckpt = CheckpointManager()

    bounds = (0.0, 0.0, config.paper.width, config.paper.height)
    regions = plan_regions(bounds, strategy=args.strategy)
    if args.regions and args.regions < len(regions):
        regions = regions[: args.regions]

    pen = PenState()
    all_chunks = []

    async with plotter:
        for i, region in enumerate(regions):
            print(f"[{i+1}/{len(regions)}] region {region.name or i}")
            chunk = await generate_region(args.prompt, region, llm, config)
            chunk, warns, pen = validate_chunk(chunk, pen, config.paper)
            metrics = score_chunk(chunk, region)
            print(f"  coverage={metrics.coverage:.2f}  segments={metrics.segment_count}")
            if metrics.coverage < 0.25 or metrics.segment_count < 10:
                print("  weak — retrying once")
                chunk = await generate_region(args.prompt, region, llm, config)
                chunk, warns, pen = validate_chunk(chunk, pen, config.paper)
            success, errors = await stream_chunk(chunk, plotter)
            print(f"  streamed {success} ok, {errors} errors")
            all_chunks.append(chunk)
            ckpt.save({
                "prompt": args.prompt,
                "region_index": i + 1,
                "completed_regions": [r.model_dump() for r in regions[: i + 1]],
                "pen_position": [0.0, 0.0],
            })

    program = merge_chunks(all_chunks, config)
    if args.out:
        Path(args.out).write_text(program.to_gcode())
        print(f"saved {args.out}  ({len(program.commands)} commands)")


def main():
    p = argparse.ArgumentParser()
    p.add_argument("--prompt", required=True)
    p.add_argument("--port", default=None)
    p.add_argument("--regions", type=int, default=4)
    p.add_argument("--strategy", default="grid_2x2",
                   choices=["grid_2x2", "grid_3x3", "quadrant", "radial"])
    p.add_argument("--simulate", action="store_true")
    p.add_argument("--out", default=None)
    args = p.parse_args()
    asyncio.run(run(args))


if __name__ == "__main__":
    main()
