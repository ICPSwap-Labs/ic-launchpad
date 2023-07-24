import Int "mo:base/Int";
import Text "mo:base/Text";
import Nat "mo:base/Nat";
import Result "mo:base/Result";

module {

    // AccountIdentifier is a 32-byte array.
    // The first 4 bytes is big-endian encoding of a CRC32 checksum of the last 28 bytes.
    public type AccountIdentifier = Blob;

    // Subaccount is an arbitrary 32-byte byte array.
    // Ledger uses subaccounts to compute the source address, which enables one
    // principal to control multiple ledger accounts.
    public type SubAccount = Blob;

    public type Page<T> = {
        totalElements: Nat;
        content: [T];
        offset: Nat;
        limit: Nat;
    };

    public type ResponseResult<T> = Result.Result<T, Text>;

    public type BoolResult = ResponseResult<Bool>;

    public type NatResult = ResponseResult<Nat>;

    public type TextResult = ResponseResult<Text>;

    public type PrincipalResult = ResponseResult<Principal>;
};