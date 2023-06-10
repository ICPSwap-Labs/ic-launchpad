import Int "mo:base/Int";
import Text "mo:base/Text";
import Nat64 "mo:base/Nat64";
import Nat "mo:base/Nat";
import Time "mo:base/Time";
import HashMap "mo:base/HashMap";
import List "mo:base/List";
import Bool "mo:base/Bool";
import Principal "mo:base/Principal";

module {

    public type CanisterView = {
        id: Text;
        name: Text;
        cycle: Nat;
    };
};