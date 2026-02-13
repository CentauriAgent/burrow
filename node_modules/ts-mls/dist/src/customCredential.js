function createCustomCredentialType(credentialId) {
    return credentialId.toString();
}
export function createCustomCredential(credentialId, data) {
    const result = {
        credentialType: createCustomCredentialType(credentialId),
        data,
    };
    return result;
}
//# sourceMappingURL=customCredential.js.map