;; identity.clar
;; Core contract for Decentralized Identity and Reputation System
;; Manages creation and verification of self-sovereign identities

;; Error codes
(define-constant ERR-NOT-AUTHORIZED (err u100))
(define-constant ERR-IDENTITY-EXISTS (err u101))
(define-constant ERR-IDENTITY-NOT-FOUND (err u102))
(define-constant ERR-EXPIRED (err u103))
(define-constant ERR-IDENTITY-INACTIVE (err u104))
(define-constant ERR-INVALID-PARAMS (err u105))
(define-constant ERR-INVALID-DID (err u106))
(define-constant ERR-INVALID-PUBLIC-KEY (err u107))
(define-constant ERR-INVALID-METADATA (err u108))
(define-constant ERR-INVALID-METHOD-ID (err u109))
(define-constant ERR-INVALID-METHOD-TYPE (err u110))
(define-constant ERR-METHOD-NOT-FOUND (err u111))
(define-constant ERR-INVALID-CONTROLLER (err u112))
(define-constant ERR-SELF-CONTROLLER (err u113))

;; Data structures

;; Identity map: principal -> identity data
(define-map identities
  { owner: principal }
  {
    did: (string-utf8 50),       ;; Decentralized identifier
    public-key: (buff 33),       ;; Public key for identity verification
    controller: principal,       ;; Controller of the identity (can be the owner or a delegate)
    created-at: uint,            ;; Block height when created
    updated-at: uint,            ;; Block height when last updated
    active: bool,                ;; Whether the identity is active
    metadata: (string-utf8 256)  ;; Additional metadata (can be JSON or IPFS hash)
  }
)

;; Controllers map: tracks additional controllers for an identity
(define-map identity-controllers
  { identity-owner: principal, controller: principal }
  { authorized: bool }
)

;; Verification methods map: associates verification methods with identities
(define-map verification-methods
  { identity-owner: principal, method-id: (string-utf8 36) }
  {
    method-type: (string-utf8 50),  ;; e.g., "Ed25519VerificationKey2020"
    public-key: (buff 33),          ;; Public key for this verification method
    created-at: uint,               ;; Block height when created
    controller: principal           ;; Who controls this verification method
  }
)

;; Identity count tracker
(define-data-var identity-count uint u0)

;; Create a new identity
(define-public (create-identity 
                (did (string-utf8 50)) 
                (public-key (buff 33))
                (metadata (string-utf8 256)))
  (begin
    ;; Basic validation - check non-empty DID and public key
    (if (< (len did) u1)
        (err ERR-INVALID-DID)
        (if (< (len public-key) u1)
            (err ERR-INVALID-PUBLIC-KEY)
            (let ((caller tx-sender)
                  (identity-exists (is-some (map-get? identities {owner: caller}))))
              (if identity-exists
                  (err ERR-IDENTITY-EXISTS)
                  (begin
                    ;; Create new identity
                    (map-set identities
                      {owner: caller}
                      {
                        did: did,
                        public-key: public-key,
                        controller: caller,
                        created-at: block-height,
                        updated-at: block-height,
                        active: true,
                        metadata: metadata
                      }
                    )
                    
                    ;; Increment identity count
                    (var-set identity-count (+ (var-get identity-count) u1))
                    
                    ;; Return success with DID
                    (ok did))))))
  ))

;; Add a controller to an identity
(define-public (add-controller (controller principal))
  (begin
    ;; Validate controller is not self
    (if (is-eq tx-sender controller)
        (err ERR-SELF-CONTROLLER)
        (let ((caller tx-sender)
              (identity (map-get? identities {owner: caller})))
          (match identity
            id (begin
                 ;; Set controller mapping
                 (map-set identity-controllers 
                   {identity-owner: caller, controller: controller} 
                   {authorized: true})
                 (ok true))
            (err ERR-IDENTITY-NOT-FOUND))))
  ))

;; Remove a controller from an identity
(define-public (remove-controller (controller principal))
  (begin
    ;; Validate controller is not self
    (if (is-eq tx-sender controller)
        (err ERR-SELF-CONTROLLER)
        (let ((caller tx-sender)
              (identity (map-get? identities {owner: caller})))
          (match identity
            id (begin
                 ;; Delete controller mapping
                 (map-delete identity-controllers {identity-owner: caller, controller: controller})
                 (ok true))
            (err ERR-IDENTITY-NOT-FOUND))))
  ))

;; Update identity metadata
(define-public (update-metadata (metadata (string-utf8 256)))
  (let ((caller tx-sender)
        (identity (map-get? identities {owner: caller})))
    (match identity
      id (begin
           ;; Update identity with new metadata
           (map-set identities
             {owner: caller}
             (merge id {
               metadata: metadata,
               updated-at: block-height
             }))
           (ok true))
      (err ERR-IDENTITY-NOT-FOUND)))
  )

;; Update identity public key
(define-public (update-public-key (public-key (buff 33)))
  (begin
    ;; Validate public key is non-empty
    (if (< (len public-key) u1)
        (err ERR-INVALID-PUBLIC-KEY)
        (let ((caller tx-sender)
              (identity (map-get? identities {owner: caller})))
          (match identity
            id (begin
                 ;; Update identity with new public key
                 (map-set identities
                   {owner: caller}
                   (merge id {
                     public-key: public-key,
                     updated-at: block-height
                   }))
                 (ok true))
            (err ERR-IDENTITY-NOT-FOUND))))
  ))

;; Deactivate an identity
(define-public (deactivate-identity)
  (let ((caller tx-sender)
        (identity (map-get? identities {owner: caller})))
    (match identity
      id (begin
           ;; Set active flag to false
           (map-set identities
             {owner: caller}
             (merge id {
               active: false,
               updated-at: block-height
             }))
           (ok true))
      (err ERR-IDENTITY-NOT-FOUND)))
  )

;; Reactivate a deactivated identity
(define-public (reactivate-identity)
  (let ((caller tx-sender)
        (identity (map-get? identities {owner: caller})))
    (match identity
      id (begin
           ;; Set active flag to true
           (map-set identities
             {owner: caller}
             (merge id {
               active: true,
               updated-at: block-height
             }))
           (ok true))
      (err ERR-IDENTITY-NOT-FOUND)))
  )

;; Add a verification method to an identity
(define-public (add-verification-method 
                (method-id (string-utf8 36))
                (method-type (string-utf8 50))
                (public-key (buff 33)))
  (begin
    ;; Basic validation
    (if (< (len method-id) u1)
        (err ERR-INVALID-METHOD-ID)
        (if (< (len method-type) u1)
            (err ERR-INVALID-METHOD-TYPE)
            (if (< (len public-key) u1)
                (err ERR-INVALID-PUBLIC-KEY)
                (let ((caller tx-sender)
                      (identity (map-get? identities {owner: caller})))
                  (match identity
                    id (begin
                         ;; Check if identity is active
                         (if (get active id)
                             (begin
                               ;; Add verification method
                               (map-set verification-methods
                                 {identity-owner: caller, method-id: method-id}
                                 {
                                   method-type: method-type,
                                   public-key: public-key,
                                   created-at: block-height,
                                   controller: caller
                                 })
                               (ok true))
                             (err ERR-IDENTITY-INACTIVE)))
                    (err ERR-IDENTITY-NOT-FOUND))))))
  ))

;; Remove a verification method
(define-public (remove-verification-method (method-id (string-utf8 36)))
  (begin
    ;; Basic validation
    (if (< (len method-id) u1)
        (err ERR-INVALID-METHOD-ID)
        (let ((caller tx-sender)
              (identity (map-get? identities {owner: caller})))
          (match identity
            id (begin
                 ;; Check if method exists before attempting to delete
                 (let ((method (map-get? verification-methods 
                                {identity-owner: caller, method-id: method-id})))
                   (match method
                     m (begin
                          ;; Delete verification method
                          (map-delete verification-methods 
                            {identity-owner: caller, method-id: method-id})
                          (ok true))
                     (err ERR-METHOD-NOT-FOUND))))
            (err ERR-IDENTITY-NOT-FOUND))))
  ))

;; Check if an identity exists and is active
(define-read-only (is-identity-valid (owner principal))
  (match (map-get? identities {owner: owner})
    identity (ok (get active identity))
    (err ERR-IDENTITY-NOT-FOUND))
  )

;; Get identity details
(define-read-only (get-identity (owner principal))
  (match (map-get? identities {owner: owner})
    identity (ok identity)
    (err ERR-IDENTITY-NOT-FOUND))
  )

;; Check if principal is authorized to control an identity
(define-read-only (is-authorized-controller (identity-owner principal) (controller principal))
  (if (is-eq identity-owner controller)
      (ok true)
      (match (map-get? identity-controllers {identity-owner: identity-owner, controller: controller})
        auth-data (ok (get authorized auth-data))
        (err ERR-NOT-AUTHORIZED)))
  )

;; Get verification method
(define-read-only (get-verification-method (owner principal) (method-id (string-utf8 36)))
  (match (map-get? verification-methods {identity-owner: owner, method-id: method-id})
    method (ok method)
    (err ERR-METHOD-NOT-FOUND))
  )

;; Get total identity count
(define-read-only (get-identity-count)
  (ok (var-get identity-count))
  )