import Array "mo:base/Array";
import Buffer "mo:base/Buffer";
import ExperimentalCycles "mo:base/ExperimentalCycles";
import HashMap "mo:base/HashMap";
import Iter "mo:base/Iter";
import Option "mo:base/Option";
import Order "mo:base/Order";
import Text "mo:base/Text";

import CommonModel "mo:commons/model/CommonModel";
import ListUtil "mo:commons/utils/ListUtils";

import Launchpad "./Launchpad";

actor LaunchpadStorage {
  private var transactionEntries : [(Text, [Launchpad.HistoryTransaction])] = [];
  private let transactionMap : HashMap.HashMap<Text, [Launchpad.HistoryTransaction]> = HashMap.fromIter<Text, [Launchpad.HistoryTransaction]>(transactionEntries.vals(), 10, Text.equal, Text.hash);
  private stable var settledLaunchpadsArry : [Launchpad.Property] = [];
  private let settledLaunchpads : Buffer.Buffer<Launchpad.Property> = Buffer.Buffer<Launchpad.Property>(0);

  public shared func addTransaction(
    managerAddress : Text,
    trans : Launchpad.HistoryTransaction,
  ) : async () {
    switch (transactionMap.get(managerAddress)) {
      case (?transactions) {
        let newTransactions : [Launchpad.HistoryTransaction] = Array.append<Launchpad.HistoryTransaction>(transactions, [trans]);
        transactionMap.put(managerAddress, newTransactions);
      };
      case (_) {
        let newTransactions : [Launchpad.HistoryTransaction] = [trans];
        transactionMap.put(managerAddress, newTransactions);
      };
    };
  };

  public query func getHistoryTransactionsByPage(
    managerAddress : Text,
    offset : Nat,
    limit : Nat,
  ) : async CommonModel.ResponseResult<CommonModel.Page<Launchpad.HistoryTransaction>> {
    let transactions : [Launchpad.HistoryTransaction] = Option.get<[Launchpad.HistoryTransaction]>(
      transactionMap.get(managerAddress),
      [],
    );
    let result : [Launchpad.HistoryTransaction] = ListUtil.arrayRange<Launchpad.HistoryTransaction>(
      ListUtil.sort<Launchpad.HistoryTransaction>(
        transactions,
        func(
          a : Launchpad.HistoryTransaction,
          b : Launchpad.HistoryTransaction,
        ) : Order.Order {
          if (
            a.time > b.time
          ) {
            #greater;
          } else if (a.time == b.time) {
            #equal;
          } else { #less };
        },
      ),
      offset,
      limit,
    );
    return #ok({
      totalElements = transactions.size();
      content = result;
      offset = offset;
      limit = limit;
    });
  };

  public shared func addSettledLaunchpad(launchpad : Launchpad.Property) : async () {
    settledLaunchpads.add(launchpad);
  };

  public query func getSettledLaunchpadsByPage(offset : Nat, limit : Nat) : async CommonModel.ResponseResult<CommonModel.Page<Launchpad.Property>> {
    let result : [Launchpad.Property] = ListUtil.arrayRange<Launchpad.Property>(
      ListUtil.sort<Launchpad.Property>(
        settledLaunchpads.toArray(),
        func(
          a : Launchpad.Property,
          b : Launchpad.Property,
        ) : Order.Order {
          if (a.endDateTime < b.endDateTime) {
            #greater;
          } else if (a.endDateTime == b.endDateTime) {
            #equal;
          } else { #less };
        },
      ),
      offset,
      limit,
    );
    return #ok({
      totalElements = settledLaunchpads.size();
      content = result;
      offset = offset;
      limit = limit;
    });
  };

  public query func cycleBalance() : async CommonModel.NatResult {
    // FIXME 0 assert msg.caller == owner;
    return #ok(ExperimentalCycles.balance());
  };
  public shared (msg) func cycleAvailable() : async CommonModel.NatResult {
    // FIXME 0 assert msg.caller == owner;
    return #ok(ExperimentalCycles.available());
  };

  system func preupgrade() {
    transactionEntries := Iter.toArray(transactionMap.entries());
    settledLaunchpadsArry := settledLaunchpads.toArray();
  };

  system func postupgrade() {
    for (item in settledLaunchpadsArry.vals()) {
      settledLaunchpads.add(item);
    };
    settledLaunchpadsArry := [];
    transactionEntries := [];
  };
};
