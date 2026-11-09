/* dns_sd.h for Windows (M1): Bonjour is not part of Windows. norns announces its OSC service with it on Linux and macOS; here the announcement is a stub that logs one line
 * (platform/windows/osc_dnssd_stub.c). only the declarations osc.cc uses. */
#ifndef VERDANDI_WIN_DNS_SD_H
#define VERDANDI_WIN_DNS_SD_H
#include <stdint.h>
typedef struct _DNSServiceRef_t *DNSServiceRef;
typedef int32_t DNSServiceErrorType;
typedef uint32_t DNSServiceFlags;
#define kDNSServiceErr_NoError 0
#define kDNSServiceErr_Unsupported (-65544)
#ifdef __cplusplus
extern "C" {
#endif
typedef void (*DNSServiceRegisterReply)(DNSServiceRef, DNSServiceFlags, DNSServiceErrorType, const char *, const char *, const char *, void *);
DNSServiceErrorType DNSServiceRegister(DNSServiceRef *sdRef, DNSServiceFlags flags, uint32_t interfaceIndex, const char *name, const char *regtype, const char *domain,
                                       const char *host, uint16_t port, uint16_t txtLen, const void *txtRecord, DNSServiceRegisterReply callBack, void *context);
void DNSServiceRefDeallocate(DNSServiceRef sdRef);
int DNSServiceRefSockFD(DNSServiceRef sdRef);
DNSServiceErrorType DNSServiceProcessResult(DNSServiceRef sdRef);
#ifdef __cplusplus
}
#endif
#endif
