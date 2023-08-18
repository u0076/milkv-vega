#include <config.h>
#include <common.h>
#include <malloc.h>
#include <net.h>
#include <command.h>
#include <fsl_mdio.h>
#include <asm/processor.h>
#include <asm/io.h>
#include <linux/io.h>

#include "xy1000_eth.h"


#define SYSCLK_CTRL					(0xE084c000)
#define SYSRST_CTRL           		(0xE084E000)     
#define BLK_SFT_RST_CSR       		(0X00L)
#define CLK_GEN_CSR           		(0X24)
#define AXI_EMAC_CLK_EN       		(18L)
#define SFT_RSTN_AXI_EMAC     		(18L)
#define LOCAL_BUS_BASE         		(0x60000000UL)      		/*!< (Local Bus ) Base Address */
#define iVtPortSrm31           		(LOCAL_BUS_BASE+0x6080be0)  //0-153 bits 146:146  152:147
#define iVtPortSrm0            		(LOCAL_BUS_BASE+0x6080800)  //0-153 bits 146:146  152:147
#define inetRegPortSrm31       		(LOCAL_BUS_BASE+0x61011f0)  //0-115 bits 4:4 
#define inetRegPortSrm0        		(LOCAL_BUS_BASE+0x6101000)  //0-115 bits 4:4
#define inetDefVlanCtl         		(LOCAL_BUS_BASE+0x6100020)  //0-162 bits 63:34
#define DMA_PORT 					(1)

#define BITS(start, end)       		((0xFFFFFFFFUL << (start)) & (0xFFFFFFFFUL >> (31U - (uint32_t)(end))))
#define DMA_REG_READ(addr)         	(*(volatile unsigned int *)(addr))
#define DMA_REG_WRITE(addr, value) 	(*(unsigned int *)(addr) = (value))	


static void dma_tx_start(struct eth_device *dev, unsigned short pkt_len, unsigned char *data);
static int dma_rx_start(struct eth_device *dev);
static void soc_dma_process_done_pkt(struct eth_device *dev);


static unsigned int tx_stat = 0;

unsigned char net_port = 0;


/***************************************************
* function	: set_words
* reg	  	��the register to be written
* N		  	��the words number of reg
* start��end��the filed of the reg to be written
* val		��the value to be written in the filed
****************************************************/
void set_words(volatile uint32_t *reg,uint32_t N,uint32_t start,uint32_t end,uint32_t val)
{
	uint32_t *p_tmp=(uint32_t *) malloc(4*N);

	for(int i=0;i<N;i++)
	{
		*(p_tmp+i) = *(reg+i);
	}

	for(int i=0;i<N;i++)
	{
		if((i==start/32) && (i==end/32))
		{
			*(p_tmp+i) &= ~ BITS(start%32,end%32);
			*(p_tmp+i) |= ((val << start%32) & BITS(start%32,end%32)); 
		}
		*(reg+i)=*(p_tmp+i);
	}
	
	free(p_tmp);
}


void get_words(volatile uint32_t *reg, uint32_t N, char *regName)
{ 
	int i = 0;
	
	printf("RegName: %s\n", regName);
	for (i = 0; i < N; ++i)
	{
		printf("%d: 0x%08x\n", i + 1, *(reg + i));
	}
}


//��ʼ������
int fh_init(struct eth_device *dev, bd_t *bd)
{	
	struct mac_eth_priv *priv = (struct mac_eth_priv *)dev->priv;

	priv->mac_eth_open = 1;										//������
												
	return 0;
}


//�ر�����
static void fh_halt(struct eth_device *dev)
{	
	struct mac_eth_priv *priv = (struct mac_eth_priv *)dev->priv;
	
	priv->mac_eth_open = 0;					
	
	return;
}


//��������
//Notice: MAC module is not a real network adapter, it will not automatic add 4bytes crc, need software does it.
static int fh_send(struct eth_device *dev, void *packet, int length)
{		
	int timeout = 10000;
	int irqstat = 0;
	struct mac_eth_priv *priv = (struct mac_eth_priv *)dev->priv;
	
	if (tx_stat == 1)
		return 1;

	dma_tx_start(dev, length + 4, packet);
	while (timeout)
	{
		irqstat = DMA_REG_READ((volatile uint32_t *)(priv->io_addr + DMA_STATUS));	//��ѯdma����״̬
		if (irqstat & IRQ_DMA_TX_END)												//�������
		{		
			tx_stat = 0;
			break;
		}
		ndelay(1000);
		timeout--;
	}

	if (timeout <= 0)
		//printf("packet send fail.\n");
   
	return 1;
}


//��������
static int fh_recv(struct eth_device *dev)
{
	int timeout = 10000;
	int irq_stat = 0;
	struct mac_eth_priv *priv = (struct mac_eth_priv *)dev->priv;

	if (dma_rx_start(dev) == 0)						
		return 1;

	while (timeout)
	{
		irq_stat = DMA_REG_READ(priv->io_addr + DMA_STATUS);			//��ѯdma����״̬
		if (irq_stat & IRQ_DMA_RX_END)									//�������
		{		
			soc_dma_process_done_pkt(dev);								//��������
			break;		
		}
		ndelay(1000);
		timeout--;
	}

	if (timeout <= 0)
		//printf("no packet receive.\n");
	
	return 1;
}


//����������ʼ��
int fh_net_initialize(bd_t *bis)
{
	struct eth_device *dev;
	struct mac_eth_priv *priv;

	//�ж�switch_en
	if ((*(volatile uint32_t *)(0x60000000 + INVISIBLE_CFG) & 0x01) != 0x01)
	{
		printf("error: switch_en is off\n");
		//set_words((volatile uint32_t *)(0x60000000 + INVISIBLE_CFG), 1, 0, 0, 0x01);
	}
	else
	{	
		set_words((volatile uint32_t *)(0x67800000 + DMA_AXI_WR_CFG), 1, 0, 7, 0x0F);
		set_words((volatile uint32_t *)(0x67800000 + DMA_AXI_RD_CFG), 1, 0, 7, 0x0F);
	
		//���������豸�ռ�
		dev = (struct eth_device *)malloc(sizeof(*dev));
		if (dev == NULL)
		{
			printf("malloc dev failed\n");
			return 0;
		}
		memset(dev, 0, sizeof(*dev));
		
		//����˽�����ݿռ�
		priv = (struct mac_eth_priv *)malloc(sizeof(*priv));
		if (priv == NULL)
		{
			printf("malloc priv failed\n");
			return 0;
		}
		memcpy(dev->enetaddr, host_addr, 6);
		
		//ʱ���븴λ
		
		//�����豸IO��ַ
		priv->io_addr = (void __iomem *)0x67800000;
		sprintf(dev->name, "xy1000_eth");
		
		//����������
		dev->priv = priv;
		dev->init = fh_init;
		dev->halt = fh_halt;
		dev->send = fh_send;
		dev->recv = fh_recv;
		
		//����dma�ռ�
		//��cache��������ȫͬ������
		//dma_addr = (unsigned char *)kmalloc(DMA_PKT_MAX_SIZE * 2, 0);
	 	//dma_addr = (unsigned char *)malloc(DMA_PKT_MAX_SIZE * 2);
		//ʹ����cache��ַ��0x40000000 ~ 0x40008000
		dma_addr = ioremap(0x40000000, DMA_PKT_MAX_SIZE * 2);
		if (dma_addr == NULL)
			printf("dma_alloc fail\n");
		
		dma_rx_buf = dma_addr;
		dma_tx_buf = dma_addr + DMA_PKT_MAX_SIZE;
		memset(dma_rx_buf, 0x00, DMA_PKT_MAX_SIZE);
		memset(dma_tx_buf, 0x00, DMA_PKT_MAX_SIZE);
		
		eth_register(dev);		//ע������
	}

	return 0;
}


//dma��������
static int dma_rx_start(struct eth_device *dev)
{
	int timeout = 10000;
	struct mac_eth_priv *priv = (struct mac_eth_priv *)dev->priv;

	while (timeout)
	{
		if ((DMA_REG_READ(priv->io_addr + DMA_STATUS)) & IRQ_DMA_RX_REQ) 			//poll rx_req_status
		{
			DMA_REG_WRITE(priv->io_addr + DMA_RX_ADDR, (unsigned int)dma_rx_buf);	//set phy addr
			DMA_REG_WRITE(priv->io_addr + DMA_RX_START, 1); 						//ʹ��dma��������
			break;
		}
		ndelay(1000);
		timeout--;
	}

	if (timeout > 0)
		return 1;
	else
		return 0;
}


//����pkg
static void soc_dma_process_done_pkt(struct eth_device *dev)			//����Ϊ�����豸
{
	int ip_len = 0;
	unsigned int RxStat, pktRxLength;
	unsigned char rx_port;
	unsigned char *data = NULL;
	struct mac_eth_priv *priv = (struct mac_eth_priv *)dev->priv;

	RxStat = DMA_REG_READ(priv->io_addr + DMA_RX_STATE);	//��ȡ����״̬
	pktRxLength = RxStat & 0xFFF; 							//(total bytes + 7) / 8 + 2(include sop and eop of pkt)		//???
	if (pktRxLength <= 2) 
		return;												//û�а�����
	
	//����֡�ṹ��˽�а�ͷ(8 Bytes) + ����(8 Bytes����) + ˽�а�β(8 Bytes)
	data = dma_rx_buf + 8;
	ip_len = ((*(dma_rx_buf + 6) & 0x3F) << 8) + *(dma_rx_buf + 7); 
	rx_port = (*(dma_rx_buf + 6) >> 6) + ((*(dma_rx_buf + 5) & 0x0F) << 2);

	if (ip_len <= 0) 
		return;												//û��ʵ������

	//if (rx_port == net_port)								//�������Զ˿�0
	net_process_received_packet(data, ip_len);				//����Э��ջ
	
	return;
}


//dma��������
static void dma_tx_start(struct eth_device *dev, unsigned short pkt_len, unsigned char *data)
{
	uint16_t pkt_align_len = 0;
	uint8_t pkt_head[8] = {0xc7, 0x04, 0xdd, 0x7b, 0x00, 0x20, 0x00, 0x40};
	struct mac_eth_priv *priv = (struct mac_eth_priv *)dev->priv;

	if (pkt_len <= 0 || pkt_len > 16375)
	{
		tx_stat = 0;
		return;
	}
	
	if (pkt_len > 64)
	{
		pkt_head[7] = (pkt_len) & 0xFF;
		pkt_head[6] = ((pkt_len) >> 8) & 0x3F;
		pkt_align_len = ((pkt_len + 7) / 8) * 8;
	}
	else
	{
		pkt_align_len = 64;
		pkt_head[7] = 0x40;
		pkt_head[6] = 0;
	}
	
	memset(dma_tx_buf, 0, pkt_align_len + 8);
	memcpy(dma_tx_buf, pkt_head, 8);
	memcpy(dma_tx_buf + 8, data, pkt_len);		//put data into tx buffer

   	DMA_REG_WRITE(priv->io_addr + DMA_TX_ADDR, (unsigned int)dma_tx_buf); 				 		//set phy addr
	DMA_REG_WRITE(priv->io_addr + DMA_TX_CFG, ((DMA_PORT << 12) + (pkt_align_len + 8) / 8));	//set lenth(data + pkt_head) and port
    DMA_REG_WRITE(priv->io_addr + DMA_TX_START, 1);                           				 	//start tx
	
	return;
}

