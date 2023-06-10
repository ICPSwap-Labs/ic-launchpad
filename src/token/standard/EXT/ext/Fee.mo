import ExtCore "./Core";
import Result "mo:base/Result";
import Bool "mo:base/Bool";

module ExtFee = {
  public type Service = actor {
    getFee: query () -> async Result.Result<ExtCore.Balance, ExtCore.CommonError>;
    setFee: shared (fee: Nat) -> async Result.Result<Bool, ExtCore.CommonError>;
    setFeeTo: shared (ExtCore.User) -> async Result.Result<Bool, ExtCore.CommonError>;
  };
};