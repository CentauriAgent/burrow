/**
 * Simple file-based storage for Burrow state.
 * Stores groups, key packages, and messages as JSON files.
 */
import { readFileSync, writeFileSync, mkdirSync, existsSync, readdirSync } from 'node:fs';
import { join } from 'node:path';
export class BurrowStore {
    baseDir;
    constructor(dataDir) {
        this.baseDir = dataDir;
        mkdirSync(join(this.baseDir, 'groups'), { recursive: true });
        mkdirSync(join(this.baseDir, 'keypackages'), { recursive: true });
        mkdirSync(join(this.baseDir, 'messages'), { recursive: true });
        mkdirSync(join(this.baseDir, 'mls-state'), { recursive: true });
    }
    // --- Groups ---
    saveGroup(group) {
        const path = join(this.baseDir, 'groups', `${group.nostrGroupId}.json`);
        writeFileSync(path, JSON.stringify(group, null, 2));
    }
    getGroup(nostrGroupId) {
        const path = join(this.baseDir, 'groups', `${nostrGroupId}.json`);
        if (!existsSync(path))
            return null;
        return JSON.parse(readFileSync(path, 'utf-8'));
    }
    listGroups() {
        const dir = join(this.baseDir, 'groups');
        if (!existsSync(dir))
            return [];
        return readdirSync(dir)
            .filter(f => f.endsWith('.json'))
            .map(f => JSON.parse(readFileSync(join(dir, f), 'utf-8')));
    }
    // --- MLS State (binary) ---
    saveMlsState(groupId, state) {
        const path = join(this.baseDir, 'mls-state', `${groupId}.bin`);
        writeFileSync(path, Buffer.from(state));
    }
    getMlsState(groupId) {
        const path = join(this.baseDir, 'mls-state', `${groupId}.bin`);
        if (!existsSync(path))
            return null;
        return new Uint8Array(readFileSync(path));
    }
    // --- Key Packages ---
    saveKeyPackage(kp) {
        const path = join(this.baseDir, 'keypackages', `${kp.id}.json`);
        writeFileSync(path, JSON.stringify(kp, null, 2));
    }
    getKeyPackage(id) {
        const path = join(this.baseDir, 'keypackages', `${id}.json`);
        if (!existsSync(path))
            return null;
        return JSON.parse(readFileSync(path, 'utf-8'));
    }
    listKeyPackages() {
        const dir = join(this.baseDir, 'keypackages');
        if (!existsSync(dir))
            return [];
        return readdirSync(dir)
            .filter(f => f.endsWith('.json'))
            .map(f => JSON.parse(readFileSync(join(dir, f), 'utf-8')));
    }
    deleteKeyPackage(id) {
        const path = join(this.baseDir, 'keypackages', `${id}.json`);
        if (existsSync(path)) {
            const { unlinkSync } = require('node:fs');
            unlinkSync(path);
        }
    }
    // --- Messages ---
    saveMessage(msg) {
        const dir = join(this.baseDir, 'messages', msg.groupId);
        mkdirSync(dir, { recursive: true });
        const path = join(dir, `${msg.createdAt}-${msg.id.slice(0, 8)}.json`);
        writeFileSync(path, JSON.stringify(msg, null, 2));
    }
    getMessages(groupId, limit = 50) {
        const dir = join(this.baseDir, 'messages', groupId);
        if (!existsSync(dir))
            return [];
        const files = readdirSync(dir)
            .filter(f => f.endsWith('.json'))
            .sort()
            .slice(-limit);
        return files.map(f => JSON.parse(readFileSync(join(dir, f), 'utf-8')));
    }
}
//# sourceMappingURL=index.js.map