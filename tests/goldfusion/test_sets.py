"""Validate generated MT4 input sets and deterministic pairwise coverage."""
import csv
import importlib.util
import unittest
from pathlib import Path

SPEC = importlib.util.spec_from_file_location('generate_sets', Path(__file__).with_name('generate_sets.py'))
module = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(module)


class SetCoverage(unittest.TestCase):
    def test_all_inputs_and_matrix(self):
        folder = module.OUTPUT
        with (folder / 'manifest.csv').open(newline='') as handle:
            manifest = list(csv.DictReader(handle))
        self.assertEqual(len(manifest), 186)
        self.assertEqual(sum(row['group'] == 'filter_matrix' for row in manifest), 32)
        for row in manifest:
            data = dict(line.split('=', 1) for line in
                        (folder / row['file']).read_text().splitlines())
            self.assertEqual(set(data), set(module.inputs), row['file'])
            self.assertFalse(data['ReversalPrimary'] == '1' and data['SignalMode'] == '1')
            self.assertFalse(data['ReversalPrimary'] == '2' and data['SignalMode'] == '0')
        pairwise = []
        for row in manifest:
            if row['group'] == 'pairwise':
                pairwise.append(dict(line.split('=', 1) for line in
                                     (folder / row['file']).read_text().splitlines()))
        self.assertEqual(len(pairwise), 64)
        for i, key in enumerate(module.factors):
            for other in module.factors[i + 1:]:
                observed = {(data[key], data[other]) for data in pairwise}
                self.assertEqual(observed,
                                 {(a, b) for a in (module.base[key], module.choices[key][0])
                                  for b in (module.base[other], module.choices[other][0])},
                                 (key, other))


if __name__ == '__main__':
    unittest.main()
