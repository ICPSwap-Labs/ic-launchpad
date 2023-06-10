import Text "mo:base/Text";
import Nat "mo:base/Nat";
import Int "mo:base/Int";
import Blob "mo:base/Blob";
import Nat64 "mo:base/Nat64";
import Principal "mo:base/Principal";
import Result "mo:base/Result";
import Error "mo:base/Error";

module {
    public type Account = { owner : Principal; subaccount : ?Subaccount };
    public type Subaccount = Blob;
    public type Amount = Nat;
    public type Memo = Blob;
    public type Timestamp = Nat64;
    public type Duration = Nat64;
    public type TxIndex = Nat;
    public type Value = { #Nat : Nat; #Int : Int; #Blob : Blob; #Text : Text; };
    public type TransferArgs = {
        from: Account;
        from_subaccount : ?Subaccount;
        to : Account;
        amount : Amount;
        fee : ?Amount;
        memo : ?Memo;
        created_at_time : ?Timestamp;
    };
    public type TransferFromArgs = {
        from: Account;
        to : Account;
        amount : Amount;
        fee : ?Amount;
        memo : ?Memo;
        created_at_time : ?Timestamp;
    };
    public type TransferError = {
        #BadFee : { expected_fee : Amount };
        #BadBurn : { min_burn_amount : Amount };
        #InsufficientFunds : { balance : Amount };
        #TooOld;
        #CreatedInFuture : { ledger_time: Timestamp };
        #Duplicate : { duplicate_of : TxIndex };
        #TemporarilyUnavailable;
        #GenericError : { error_code : Nat; message : Text };
    };
    public type TransferResult = {
        #Ok  : TxIndex;
        #Err : TransferError;
    };
    public type ApproveArgs = {
        from_subaccount : ?Subaccount;
        spender : Principal;
        amount : Amount;
        fee : ?Amount;
        memo : ?Memo;
        created_at_time : ?Timestamp;
    };
    public type ApproveError = {
        #BadFee : { expected_fee : Amount };
        #InsufficientFunds : { balance : Amount };
        #TooOld;
        #CreatedInFuture : { ledger_time: Timestamp };
        #Duplicate : { duplicate_of : TxIndex };
        #TemporarilyUnavailable;
        #GenericError : { error_code : Nat; message : Text };
    };
    public type ApproveResult = {
        #Ok  : TxIndex;
        #Err : ApproveError;
    };
    public type TransferFromError = {
        #BadFee : { expected_fee : Amount };
        #BadBurn : { min_burn_amount : Amount };
        #InsufficientFunds : { balance : Amount };
        #InsufficientAllowance : { allowance : Amount };
        #TooOld;
        #CreatedInFuture : { ledger_time: Timestamp };
        #Duplicate : { duplicate_of : TxIndex };
        #TemporarilyUnavailable;
        #GenericError : { error_code : Nat; message : Text };
    };
    public type TransferFromResult = {
        #Ok  : TxIndex;
        #Err : TransferFromError;
    };
    public type AllowanceArgs = {
        account : Account;
        spender : Principal;
    };

    public class TokenAdapter() {
        public func valid(): async Bool { throw Error.reject("Unsupport method 'valid'.") };
        public func balanceOf(account : Account): async Amount { throw Error.reject("Unsupport method 'balanceOf'.") };
        public func totalSupply(): async Amount { throw Error.reject("Unsupport method 'totalSupply'.") };
        public func symbol(): async Text { throw Error.reject("Unsupport method 'symbol'.") };
        public func decimals(): async Nat8 { throw Error.reject("Unsupport method 'decimals'.") };
        public func fee(): async Nat { throw Error.reject("Unsupport method 'fee'.") };
        public func metadata(): async [(Text, Value)] { throw Error.reject("Unsupport method 'metadata'.") };
        public func transfer(args: TransferArgs): async TransferResult { throw Error.reject("Unsupport method 'transfer'.") };
        public func approve(args: ApproveArgs): async ApproveResult { throw Error.reject("Unsupport method 'approve'.") };
        public func transferFrom(args: TransferFromArgs): async TransferFromResult { throw Error.reject("Unsupport method 'transferFrom'.") };
    }
}