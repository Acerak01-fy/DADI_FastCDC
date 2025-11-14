#!/usr/bin/env python3
"""
FastCDC Test Result Analyzer
Analyzes the compression results from FastCDC tests
"""

import sys
import csv
from pathlib import Path
from typing import Dict, List, Tuple

def parse_results(csv_file: Path) -> List[Dict]:
    """Parse the results CSV file"""
    results = []
    with open(csv_file, 'r') as f:
        reader = csv.DictReader(f)
        for row in reader:
            results.append({
                'test_name': row['test_name'],
                'input_size': int(row['input_size']),
                'output_size': int(row['output_size']),
                'ratio': float(row['ratio']),
                'duration': float(row['duration'])
            })
    return results

def format_size(size_bytes: int) -> str:
    """Format bytes to human-readable size"""
    for unit in ['B', 'KB', 'MB', 'GB']:
        if size_bytes < 1024.0:
            return f"{size_bytes:.2f} {unit}"
        size_bytes /= 1024.0
    return f"{size_bytes:.2f} TB"

def analyze_results(results: List[Dict]):
    """Analyze and display results"""
    
    print("=" * 80)
    print("FastCDC vs Fixed-size Chunking Analysis")
    print("=" * 80)
    
    # Group by size
    sizes = set()
    for r in results:
        if 'mb' in r['test_name']:
            size = r['test_name'].split('_')[-1].replace('mb', '')
            sizes.add(int(size))
    
    for size in sorted(sizes):
        print(f"\n{'─' * 80}")
        print(f"Test Size: {size}MB")
        print(f"{'─' * 80}")
        
        # Get fixed and FastCDC results for this size
        fixed = next((r for r in results if f'fixed_{size}mb' == r['test_name']), None)
        fastcdc_configs = [r for r in results if f'fastcdc_' in r['test_name'] and f'_{size}mb' in r['test_name']]
        
        if fixed:
            print(f"\n📊 Fixed-size Chunking (Baseline):")
            print(f"   Input:  {format_size(fixed['input_size'])}")
            print(f"   Output: {format_size(fixed['output_size'])}")
            print(f"   Ratio:  {fixed['ratio']:.2f}%")
            print(f"   Time:   {fixed['duration']:.3f}s")
        
        if fastcdc_configs:
            print(f"\n🚀 FastCDC Results:")
            for fc in fastcdc_configs:
                config_name = fc['test_name'].replace(f'fastcdc_', '').replace(f'_{size}mb', '')
                print(f"\n   Configuration: {config_name}")
                print(f"   Input:  {format_size(fc['input_size'])}")
                print(f"   Output: {format_size(fc['output_size'])}")
                print(f"   Ratio:  {fc['ratio']:.2f}%")
                print(f"   Time:   {fc['duration']:.3f}s")
                
                if fixed:
                    improvement = fixed['ratio'] - fc['ratio']
                    speed_ratio = fixed['duration'] / fc['duration']
                    
                    print(f"\n   📈 Comparison with Fixed-size:")
                    if improvement > 0:
                        print(f"      ✓ Compression: {improvement:.2f}% better ({fc['ratio']:.2f}% vs {fixed['ratio']:.2f}%)")
                    elif improvement < 0:
                        print(f"      ✗ Compression: {abs(improvement):.2f}% worse ({fc['ratio']:.2f}% vs {fixed['ratio']:.2f}%)")
                    else:
                        print(f"      = Compression: Same as fixed-size")
                    
                    if speed_ratio > 1:
                        print(f"      ⚡ Speed: {speed_ratio:.2f}x faster")
                    elif speed_ratio < 1:
                        print(f"      🐌 Speed: {1/speed_ratio:.2f}x slower")
                    else:
                        print(f"      = Speed: Same as fixed-size")
    
    # Overall statistics
    print(f"\n{'=' * 80}")
    print("Overall Statistics")
    print(f"{'=' * 80}")
    
    fixed_results = [r for r in results if 'fixed_' in r['test_name']]
    fastcdc_results = [r for r in results if 'fastcdc_default' in r['test_name']]
    
    if fixed_results and fastcdc_results:
        avg_fixed_ratio = sum(r['ratio'] for r in fixed_results) / len(fixed_results)
        avg_fastcdc_ratio = sum(r['ratio'] for r in fastcdc_results) / len(fastcdc_results)
        avg_improvement = avg_fixed_ratio - avg_fastcdc_ratio
        
        print(f"\nAverage Compression Ratio:")
        print(f"   Fixed-size: {avg_fixed_ratio:.2f}%")
        print(f"   FastCDC:    {avg_fastcdc_ratio:.2f}%")
        print(f"   Improvement: {avg_improvement:.2f}%")
        
        avg_fixed_time = sum(r['duration'] for r in fixed_results) / len(fixed_results)
        avg_fastcdc_time = sum(r['duration'] for r in fastcdc_results) / len(fastcdc_results)
        
        print(f"\nAverage Compression Time:")
        print(f"   Fixed-size: {avg_fixed_time:.3f}s")
        print(f"   FastCDC:    {avg_fastcdc_time:.3f}s")
        print(f"   Ratio:      {avg_fixed_time/avg_fastcdc_time:.2f}x")
    
    # Deduplication effectiveness analysis
    print(f"\n{'=' * 80}")
    print("Deduplication Effectiveness")
    print(f"{'=' * 80}")
    print("\nNote: Better deduplication = Lower compression ratio")
    print("(More duplicate data detected and removed)")
    
    for size in sorted(sizes):
        fixed = next((r for r in results if f'fixed_{size}mb' == r['test_name']), None)
        fastcdc = next((r for r in results if f'fastcdc_default_{size}mb' == r['test_name']), None)
        
        if fixed and fastcdc:
            dedup_improvement = ((fixed['output_size'] - fastcdc['output_size']) / fixed['output_size']) * 100
            print(f"\n{size}MB test:")
            print(f"   Deduplication improvement: {dedup_improvement:.2f}%")
            if dedup_improvement > 0:
                print(f"   ✓ FastCDC detected {dedup_improvement:.2f}% more duplicates")
            elif dedup_improvement < 0:
                print(f"   ✗ Fixed-size detected {abs(dedup_improvement):.2f}% more duplicates")

def main():
    if len(sys.argv) > 1:
        csv_file = Path(sys.argv[1])
    else:
        csv_file = Path('/tmp') / [d for d in Path('/tmp').glob('fastcdc_test_*')][0] / 'results.csv'
    
    if not csv_file.exists():
        print(f"Error: {csv_file} not found")
        print("Usage: python3 analyze_fastcdc_results.py [results.csv]")
        sys.exit(1)
    
    results = parse_results(csv_file)
    analyze_results(results)
    
    print(f"\n{'=' * 80}")
    print(f"Analysis complete! Results from: {csv_file}")
    print(f"{'=' * 80}\n")

if __name__ == '__main__':
    main()
