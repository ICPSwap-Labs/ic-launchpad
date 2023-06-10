import Text "mo:base/Text";

import Types "./TokenTypes";
import DIP20 "./standard/DIP20";
import EXT "./standard/EXT";
import ICRC1 "./standard/ICRC-1";
import ICRC2 "./standard/ICRC-2";
import ICP "./standard/ICP";
import Debug "mo:base/Debug";

module TokenFactory {

    public let EXT_STANDARD : Text = "EXT";
    public let DIP20_STANDARD : Text = "DIP20";
    public let ICP_STANDARD : Text = "ICP";
    public let ICRC1_STANDARD : Text = "ICRC1";
    public let ICRC2_STANDARD : Text = "ICRC2";


    public func getAdapter(address: Text, standard: Text): Types.TokenAdapter {
        if (standard == "DIP20") {
            Debug.print("==> dip20 adapter");
            return DIP20.DIP20TokenAdapter(address);
        } else if (standard == "DIP20-WICP") {
            Debug.print("==> dip20 adapter");
            return DIP20.DIP20TokenAdapter(address);
        } else if (standard == "DIP20-XTC") {
            Debug.print("==> dip20 adapter");
            return DIP20.DIP20TokenAdapter(address);
        } else if (standard == "EXT") {
            Debug.print("==> ext adapter");
            return EXT.EXTTokenAdapter(address);
        } else if (standard == "ICRC1") {
            Debug.print("==> icrc1 adapter");
            return ICRC1.ICRC1TokenAdapter(address);
        } else if (standard == "ICRC2") {
            Debug.print("==> icrc2 adapter");
            return ICRC2.ICRC2TokenAdapter(address);
        } else if (standard == "ICP") {
            Debug.print("==> icp adapter");
            return ICP.ICPTokenAdapter();
        };
        return Types.TokenAdapter();
    };
    
};