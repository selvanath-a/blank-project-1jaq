;; (use-trait nft-trait 'ST1PQHQKV0RJXZFY1DGX8MNSNYVE3VGZJSRTPGZGM.nft-trait.nft-trait)
;; (use-trait nft-ownable-trait 'ST3MSZPVNN783PB6D02DK5879RWPA1E36Z53VA2E.nft-ownable-trait.nft-ownable-trait)
;; (use-trait nft-trait 'ST1PQHQKV0RJXZFY1DGX8MNSNYVE3VGZJSRTPGZGM.nft-trait.nft-trait)
;; (use-trait nft-ownable-trait 'ST1FK5YJHH3NARMGQZ469JZAV4S4WDJ4P4DBKHYF5.nft-ownable-trait.nft-ownable-trait)
(use-trait nft-trait .nft-trait.nft-trait)
(use-trait nft-ownable-trait .nft-ownable-trait.nft-ownable-trait)
(define-constant ERR-NOT-AUTHORIZED	(err u1000))
(define-constant ERR-NOT-REGISTERED-COLLECTION	(err u1001))
(define-constant ERR-BRIDGE-PASSED	(err u1002))
(define-constant ERR-NOT-SAME-PRINCIPAL	(err u1003))
(define-constant ERR-NOT-OWNER	(err u1004))
(define-constant ERR-BRIDGED-ALREADY (err u1005))
(define-constant ERR-INVALID-ADDRESS (err u1006))
(define-constant ERR-INVALID-CONTRACT (err u1007))
(define-constant ERR-VERIFICATION-FAILED (err u1008))
(define-constant ERR-STX-TRANSFER-FAILED (err u1009))
(define-data-var contract-owner principal tx-sender)
(define-data-var contract-operator principal tx-sender)
(define-constant contract-address (as-contract tx-sender))
(define-data-var payment-account principal tx-sender)
(define-data-var bridge-fee uint u5000000) ;; 5 usd
(define-data-var collection-count uint u0)
(define-map bridge-nonce {collection: principal, id: uint} uint)
(define-map bridge-take-fee {collection: principal, id: uint, nonce: uint} bool)
(define-map bridged-to {collection: principal, id: uint, nonce: uint} principal)
(define-map collections {id: uint} principal)
(define-map collection-ids {collection: principal} uint)
(define-map chain-contract-addresses {collection: principal,chain:(string-ascii 10)} ( string-ascii 50))
(define-map collection-origin principal (string-ascii 10))

(define-read-only (get-collection-origin (nft-asset-contract <nft-trait>)) (map-get? collection-origin (contract-of nft-asset-contract)))

(define-read-only (is-origin-chain-stx (nft-asset-contract <nft-trait>)) 
	(is-eq (default-to "ETH" (get-collection-origin nft-asset-contract)) "STX")
)
(define-read-only (get-chain-contract-address (nft-asset-contract <nft-trait>) (chain (string-ascii 10)))
	(map-get? chain-contract-addresses {collection: (contract-of nft-asset-contract), chain: chain})
)

(define-read-only (get-contract-owner) (var-get contract-owner))

(define-read-only (get-collection-id (nft-asset-contract <nft-trait>)) (map-get? collection-ids {collection: ( contract-of nft-asset-contract)}))

(define-private	(check-is-owner)
	(ok (asserts! (and (is-eq tx-sender (var-get contract-owner)) (is-eq tx-sender contract-caller)) ERR-NOT-OWNER))
)

(define-private	(check-is-operator)
	(ok (asserts! (and (is-eq tx-sender (var-get contract-operator)) (is-eq tx-sender contract-caller)) ERR-NOT-AUTHORIZED))
)

(define-private	(check-is-valid-address (address principal))
	;; Check if principal is in the same network as the contract
	(ok (asserts! (is-standard address) ERR-INVALID-ADDRESS))
)

(define-public (send-to-bridge (nft-asset-contract <nft-trait>) (nft-id uint) (take-fee bool) (dest-chain (string-ascii 10)) (dest-address (string-ascii 128)) (bridge-tx-id (string-ascii 32)))
	(let
		((collection-id (map-get? collection-ids {collection: ( contract-of nft-asset-contract)}))
		(nonce (default-to u0 (map-get? bridge-nonce {collection: ( contract-of nft-asset-contract),id: nft-id}))))
			
		(asserts! (is-some collection-id) ERR-NOT-REGISTERED-COLLECTION)
		
		(map-set bridge-take-fee {collection: ( contract-of nft-asset-contract),id: nft-id,nonce: nonce} take-fee)
		(map-set bridge-nonce {collection: ( contract-of nft-asset-contract),id: nft-id} (+ nonce u1))

		(if
			(and (is-eq take-fee true) (not (is-eq tx-sender (var-get payment-account))))
			(begin
				(try! (stx-transfer? (get-bridge-fee (var-get bridge-fee)) tx-sender (var-get payment-account)))
			)
			false
		)
		(try! (contract-call? nft-asset-contract transfer nft-id tx-sender contract-address))
		(print {event:"send-to-bridge",collection: ( contract-of nft-asset-contract),nft-id: nft-id,take-fee: take-fee,dest-chain:dest-chain,dest-address: dest-address,origin-chain: (get-collection-origin nft-asset-contract), bridge-tx-id:bridge-tx-id,nonce: nonce})
		(ok true)
	)
)

(define-public (pull-from-bridge (nft-asset-contract <nft-trait>) (nft-admin-contract  (optional <nft-ownable-trait>)) (nft-id uint) (take-fee bool) (dest-address principal) (bridge-tx-id (string-ascii 32)))
	(let
		((collection-id (map-get? collection-ids {collection: ( contract-of nft-asset-contract)}))
		(nonce (default-to u0 (map-get? bridge-nonce {collection: ( contract-of nft-asset-contract),id: nft-id})))
		(can-mint  (and (not (is-origin-chain-stx nft-asset-contract)) (is-some nft-admin-contract)))
		)
		(try! (check-is-valid-address dest-address))
		(try! (check-is-operator))
		(asserts! (is-some collection-id) ERR-NOT-REGISTERED-COLLECTION)
		(begin
			(if (and can-mint ( is-none (try! (contract-call? nft-asset-contract get-owner nft-id))))
			(try! (mint-token nft-admin-contract nft-id dest-address))
			(try! (as-contract (contract-call? nft-asset-contract transfer nft-id contract-address dest-address)))
			)
		)
		(map-set bridge-nonce {collection: ( contract-of nft-asset-contract),id: nft-id} (+ nonce u1))
		(map-set bridge-take-fee {collection: ( contract-of nft-asset-contract),id: nft-id,nonce: nonce} take-fee)
		(map-set bridged-to {collection: ( contract-of nft-asset-contract),id: nft-id,nonce: nonce} dest-address)
		(print {event:"pull-from-bridge",collection: ( contract-of nft-asset-contract),id: nft-id,take-fee: take-fee,dest: dest-address,bridge-tx-id:bridge-tx-id,nonce: nonce})
		(ok true)
	)
)

(define-private (mint-token (nft-admin-contract  (optional <nft-ownable-trait>)) (nft-id uint) (dest-address principal)) 
(let ((admin (unwrap! nft-admin-contract ERR-INVALID-CONTRACT)))
	(as-contract (contract-call? admin mint nft-id dest-address)))
)

(define-public (pay-bridge-fees (nft-asset-contract <nft-trait>) (nft-id uint))
	(let
		((nonce (default-to u0 (map-get? bridge-nonce {collection: ( contract-of nft-asset-contract),id: nft-id})))
		(take-fee (default-to false (map-get? bridge-take-fee {collection: ( contract-of nft-asset-contract),id: nft-id,nonce: nonce})))
		(dest-address (map-get? bridged-to {collection: ( contract-of nft-asset-contract),id: nft-id,nonce: nonce}))
		)
			(if (not (is-eq tx-sender (var-get payment-account)))
			(begin
				(try! (stx-transfer? (get-bridge-fee (var-get bridge-fee)) tx-sender (var-get payment-account)))
			)
			false
			)
		(print {event: "pay-bridge-fees",collection: ( contract-of nft-asset-contract),id: nft-id,take-fee: take-fee,dest: dest-address,nonce: nonce})
		(ok true)
	)
)

				
(define-public (add-collection (nft-asset-contract <nft-trait>) (origin-chain (string-ascii 10)))
	(begin
		(try! (check-is-operator))
		(try! (check-is-valid-address (contract-of nft-asset-contract)))
		(asserts! (is-none (map-get? collection-ids {collection: ( contract-of nft-asset-contract)})) ERR-BRIDGE-PASSED)
		(map-set collection-ids {collection:( contract-of nft-asset-contract)} (var-get collection-count))
		(map-set collections {id: ( var-get collection-count)} (contract-of nft-asset-contract))
		(map-set collection-origin (contract-of nft-asset-contract) origin-chain)
		(print {event: "add-collection",id: ( var-get collection-count),collection: ( contract-of nft-asset-contract), origin:origin-chain})
		(var-set collection-count (+ (var-get collection-count) u1))
		(ok true)
	)
)
(define-public (set-collection-origin (nft-asset-contract <nft-trait>) (origin-chain (string-ascii 10))) 
	(begin
		(try! (check-is-operator))
		(asserts! (is-some (map-get? collection-ids {collection: ( contract-of nft-asset-contract)})) ERR-NOT-REGISTERED-COLLECTION)
		(ok (map-set collection-origin (contract-of nft-asset-contract) origin-chain))
	 )
)

;; (define-public (set-chain-contract-address  (nft-asset-contract <nft-trait>) (chain (string-ascii 10)) (chain-contract-address (string-ascii 50)))
;; 	(begin
;; 		(try! (check-is-operator))
;; 		(asserts! (is-some (map-get? collection-ids {collection: ( contract-of nft-asset-contract)})) ERR-NOT-REGISTERED-COLLECTION)
;; 		(ok (map-set chain-contract-addresses {collection: ( contract-of nft-asset-contract), chain: chain} chain-contract-address)))
;; )

(define-public (set-payment-account (new-payment-account principal))
	(begin
		(try! (check-is-operator))
		(try! (check-is-valid-address new-payment-account))
		(var-set payment-account new-payment-account)
		(ok true)
	)
)

(define-public (set-contract-owner (new-owner principal))
	(begin
		(try! (check-is-owner))
		(try! (check-is-valid-address new-owner))
		(ok (var-set contract-owner new-owner))
	)
)

(define-public (set-contract-operator (new-operator principal))
	(begin
		(try! (check-is-owner))
		(try! (check-is-valid-address new-operator))
		(ok (var-set contract-operator new-operator))
	)
)

(define-public (set-bridge-fee (fee uint))
	(begin
		(try! (check-is-operator))
		(var-set bridge-fee fee)
		(ok true)
	)
)

;; (define-public (transfer-stx (to-address principal) (amount uint))
;; 	(begin
;; 		(try! (check-is-owner))
;; 		(try! (check-is-valid-address to-address))
;; 		(try! (as-contract (stx-transfer? amount contract-address to-address)))
;; 		(ok true)
;; 	)
;; )
(define-read-only (get-balance)
    (begin
        (try! (check-is-operator))
        (ok (stx-get-balance (as-contract tx-sender)))
    )
)
;; The administrator can transfer the balance in the contract to another address
(define-public (transfer-balance (recipient principal))
    (let
        (
            (balance (stx-get-balance (as-contract tx-sender)))
        )
		(try! (check-is-operator))
		(try! (check-is-valid-address recipient))
        ;; (asserts! (is-eq (var-get administrator) tx-sender) not-allowed)
        (unwrap! (stx-transfer? balance (as-contract tx-sender) recipient) ERR-STX-TRANSFER-FAILED)
        (print {event: "transfer-balance", recipient: recipient, balance: balance})
        (ok balance)
    )
)

(define-read-only (get-bridge-fee (usd-value uint))
	(let
		((stx-price (contract-call? .arkadiko-oracle-v1 get-price "STX")))
		;; ((stx-price (contract-call? 'ST1PQHQKV0RJXZFY1DGX8MNSNYVE3VGZJSRTPGZGM.arkadiko-oracle-v1 get-price "STX")))
			;; ((stx-price (contract-call? 'ST1FK5YJHH3NARMGQZ469JZAV4S4WDJ4P4DBKHYF5.arkadiko-oracle-v1 get-price "STX")))
		(default-to u0 (some (/ (* usd-value (get decimals stx-price)) (get last-price stx-price))))
	)
)

(define-read-only (get-nonce (nft-asset-contract <nft-trait>) (nft-id uint))
	(let
		(
			(nonce (default-to u0 (map-get? bridge-nonce {collection: ( contract-of nft-asset-contract),id: nft-id})))
		)
		(ok nonce)
	)
)

(define-read-only (get-take-fee (nft-asset-contract <nft-trait>) (nft-id uint) (nonce uint))
	(let
		(
			(take-fee (default-to true (map-get? bridge-take-fee {collection: ( contract-of nft-asset-contract),id: nft-id,nonce: nonce})))
		)
		(ok take-fee)
	)
)

(define-read-only (get-claimer (nft-asset-contract <nft-trait>) (nft-id uint))
	(let
		(
		(nonce (default-to u0 (map-get? bridge-nonce {collection: (contract-of nft-asset-contract),id: nft-id})))
		(dest-address (map-get? bridged-to {collection: ( contract-of nft-asset-contract),id: nft-id,nonce: nonce}))
		)
		(ok dest-address)
	)
)

(define-public (transfer-collection-ownership (nft-asset-contract <nft-ownable-trait>) (new-admin principal))
	(begin
		(try! (check-is-owner))
		(asserts! (is-some (map-get? collection-ids {collection: ( contract-of nft-asset-contract)})) ERR-NOT-REGISTERED-COLLECTION)
		(try! (check-is-valid-address new-admin))
		(try! (as-contract (contract-call? nft-asset-contract set-contract-owner new-admin)))
		(print {event: "transfer-collection-ownership",collection: ( contract-of nft-asset-contract),new-admin:new-admin})
		(ok true)
	)
)