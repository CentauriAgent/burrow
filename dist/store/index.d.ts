/**
 * Simple file-based storage for Burrow state.
 * Stores groups, key packages, and messages as JSON files.
 */
import type { StoredGroup, StoredKeyPackage, GroupMessage } from '../types/index.js';
export declare class BurrowStore {
    private baseDir;
    constructor(dataDir: string);
    saveGroup(group: StoredGroup): void;
    getGroup(nostrGroupId: string): StoredGroup | null;
    listGroups(): StoredGroup[];
    saveMlsState(groupId: string, state: Uint8Array): void;
    getMlsState(groupId: string): Uint8Array | null;
    saveKeyPackage(kp: StoredKeyPackage): void;
    getKeyPackage(id: string): StoredKeyPackage | null;
    listKeyPackages(): StoredKeyPackage[];
    deleteKeyPackage(id: string): void;
    saveMessage(msg: GroupMessage): void;
    getMessages(groupId: string, limit?: number): GroupMessage[];
}
//# sourceMappingURL=index.d.ts.map