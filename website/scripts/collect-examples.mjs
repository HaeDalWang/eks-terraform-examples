/**
 * 빌드 전 실행: 레포 루트 디렉토리를 스캔하여 예제 메타데이터를 생성합니다.
 * README.md가 있는 디렉토리 = 예제 페이지
 */
import fs from 'fs';
import path from 'path';

const ROOT = path.resolve(import.meta.dirname, '../../');
const OUT_DIR = path.resolve(import.meta.dirname, '../src/data');

// 예제가 아닌 디렉토리 (스캔에서 제외)
const IGNORE = new Set([
  'website', 'design-sample', 'scripts', 'customer', 'yamls',
  'seungdo-helm-chart', '.git', 'node_modules', '.terraform',
]);

// 카테고리 자동 분류
const CATEGORY_MAP = {
  'lgtm-stack': { category: 'Observability', icon: 'monitoring', color: 'secondary' },
  'istio-mesh': { category: 'Service Mesh', icon: 'lan', color: 'primary' },
  'envoy-gateway-nlb-integration': { category: 'Gateway', icon: 'hub', color: 'tertiary' },
  'cilium-cni': { category: 'CNI / Networking', icon: 'settings_ethernet', color: 'primary' },
  'mlops': { category: 'MLOps', icon: 'psychology', color: 'tertiary' },
  'seungdo': { category: 'PoC', icon: 'science', color: 'secondary' },
};

function extractTitle(readmeContent) {
  const match = readmeContent.match(/^#\s+(.+)$/m);
  return match ? match[1].trim() : null;
}

function extractDescription(readmeContent) {
  // 첫 번째 heading 이후 첫 번째 paragraph
  const lines = readmeContent.split('\n');
  let pastTitle = false;
  for (const line of lines) {
    if (line.startsWith('# ')) { pastTitle = true; continue; }
    if (pastTitle && line.trim() && !line.startsWith('#') && !line.startsWith('```') && !line.startsWith('|')) {
      return line.trim();
    }
  }
  return '';
}

function countTfFiles(dirPath) {
  const files = [];
  function walk(dir) {
    if (!fs.existsSync(dir)) return;
    for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
      if (entry.name.startsWith('.')) continue;
      const full = path.join(dir, entry.name);
      if (entry.isDirectory()) walk(full);
      else if (entry.name.endsWith('.tf') || entry.name.endsWith('.yaml') || entry.name.endsWith('.yml')) {
        files.push(path.relative(dirPath, full));
      }
    }
  }
  walk(dirPath);
  return files;
}

function getSubDirs(dirPath) {
  if (!fs.existsSync(dirPath)) return [];
  return fs.readdirSync(dirPath, { withFileTypes: true })
    .filter(d => d.isDirectory() && !d.name.startsWith('.') && d.name !== 'helm-values')
    .map(d => d.name);
}

// Main
const examples = [];

for (const entry of fs.readdirSync(ROOT, { withFileTypes: true })) {
  if (!entry.isDirectory() || IGNORE.has(entry.name) || entry.name.startsWith('.')) continue;

  const dirPath = path.join(ROOT, entry.name);

  // README.md가 있는 디렉토리만
  const readmePath = path.join(dirPath, 'README.md');
  if (!fs.existsSync(readmePath)) continue;

  const readmeContent = fs.readFileSync(readmePath, 'utf-8');
  const slug = entry.name;
  const meta = CATEGORY_MAP[slug] || { category: 'General', icon: 'folder', color: 'primary' };
  const subDirs = getSubDirs(dirPath);
  const tfFiles = countTfFiles(dirPath);

  // 멀티 클러스터 여부
  const isMultiCluster = subDirs.some(d =>
    ['central', 'agent', 'primary', 'remote', 'mgmt', 'workload'].includes(d)
  );

  examples.push({
    slug,
    title: extractTitle(readmeContent) || slug,
    description: extractDescription(readmeContent),
    category: meta.category,
    icon: meta.icon,
    color: meta.color,
    subDirs,
    fileCount: tfFiles.length,
    isMultiCluster,
    readmePath: `../../${slug}/README.md`,
  });
}

// Sort: multi-cluster first, then alphabetically
examples.sort((a, b) => {
  if (a.isMultiCluster !== b.isMultiCluster) return b.isMultiCluster ? 1 : -1;
  return a.slug.localeCompare(b.slug);
});

// Write
fs.mkdirSync(OUT_DIR, { recursive: true });
fs.writeFileSync(
  path.join(OUT_DIR, 'examples.json'),
  JSON.stringify(examples, null, 2)
);

console.log(`[collect-examples] ${examples.length} examples found:`);
examples.forEach(e => console.log(`  - ${e.slug} (${e.category}, ${e.fileCount} files)`));
