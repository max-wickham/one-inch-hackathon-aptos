// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

library ExtensionsLib {

    enum DynamicField {
        MakerAssetSuffix,
        TakerAssetSuffix,
        MakingAmountData,
        TakingAmountData,
        Predicate,
        MakerPermit,
        PreInteractionData,
        PostInteractionData,
        CustomData
    }


    function newExtensions(
        bytes memory makerAssetSuffix,
        bytes memory takerAssetSuffix,
        bytes memory makingAmountData,
        bytes memory takingAmountData,
        bytes memory predicate,
        bytes memory makerPermit,
        bytes memory preInteractionData,
        bytes memory postInteractionData,
        bytes memory customData
    ) public pure returns (bytes memory) {
        uint offsets = 0;
        uint total;
        offsets |= (makerAssetSuffix.length + total << 0);
        total += makerAssetSuffix.length;
        offsets |= (takerAssetSuffix.length + total << 32);
        total += takerAssetSuffix.length;
        offsets |= (makingAmountData.length + total << 64);
        total += makingAmountData.length;
        offsets |= (takingAmountData.length + total << 96);
        total += takingAmountData.length;
        offsets |= (predicate.length + total << 128);
        total += predicate.length;
        offsets |= (makerPermit.length + total << 160);
        total += makerPermit.length;
        offsets |= (preInteractionData.length + total << 192);
        total += preInteractionData.length;
        offsets |= (postInteractionData.length + total << 224);
        return abi.encodePacked(
            offsets,
            makerAssetSuffix,
            takerAssetSuffix,
            makingAmountData,
            takingAmountData,
            predicate,
            makerPermit,
            preInteractionData,
            postInteractionData,
            customData
        );
    }

}