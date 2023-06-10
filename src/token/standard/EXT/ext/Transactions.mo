import ExtCore "./Core";
import ExtCommon "./Common";
import Result "mo:base/Result";


module ExtTransactions = {
  public type Transaction = {
      index: Nat;
      from: ExtCore.AccountIdentifier;
      to: ExtCore.AccountIdentifier;
      amount: ExtCore.Balance;
      fee: ExtCore.Balance;
      timestamp: Int;
      hash: Text;
      memo: ?Blob;
      status: Text;
      transType: TransType;
  };
  public type TransType = {
    #approve;
    #transfer;
    #mint;
    #burn;
  };
  public type TransactionRequest = {
      offset: ?Nat;
      limit: ?Nat;
      user: ?ExtCore.User;
      hash: ?Text;
      index: ?Nat;
  };
  
  public type TransactionsActor = actor {
      transactions : query (request : TransactionRequest) -> async Result.Result<ExtCommon.Page<Transaction>, ExtCore.CommonError>;
  };
};